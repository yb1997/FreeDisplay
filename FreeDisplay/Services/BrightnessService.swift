import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

@_silgen_name("CGDisplayIOServicePort")
private func CGDisplayIOServicePort(_ display: CGDirectDisplayID) -> io_service_t

// DisplayServices private API — the only way to read/set built-in brightness on Apple Silicon,
// where there are no IODisplayConnect services and CGDisplayIOServicePort is 0.
// (CoreDisplay_Display_Get/SetUserBrightness exist but are no-ops there: Get always returns 1.0.)
// Loaded via dlsym at runtime (see lessons L-026); nil if the symbol is missing.
// Both return 0 on success and an error code for displays they can't drive (e.g. externals).
private nonisolated(unsafe) let displayServicesHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

private let _DisplayServicesGetBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
    guard let handle = displayServicesHandle,
          let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
}()

private let _DisplayServicesSetBrightness: (@convention(c) (CGDirectDisplayID, Float) -> Int32)? = {
    guard let handle = displayServicesHandle,
          let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)
}()

/// Built-in display brightness (0.0–1.0) via DisplayServices, or nil if unavailable.
func displayServicesBrightness(for displayID: CGDirectDisplayID) -> Double? {
    guard let get = _DisplayServicesGetBrightness else { return nil }
    var value: Float = 0
    guard get(displayID, &value) == 0 else { return nil }
    return Double(min(1, max(0, value)))
}

/// Sets built-in display brightness (0.0–1.0) via DisplayServices. Returns false on failure.
@discardableResult
func setDisplayServicesBrightness(_ value: Double, for displayID: CGDirectDisplayID) -> Bool {
    guard let set = _DisplayServicesSetBrightness else { return false }
    return set(displayID, Float(min(1, max(0, value)))) == 0
}

// MARK: - BrightnessAnimator

/// Manages smooth brightness transitions for a single display.
/// Cancels any in-progress animation when a new one starts, so rapid presses stay responsive.
/// All methods must be called on the main thread.
final class BrightnessAnimator: @unchecked Sendable {
    private var timer: Timer?
    private var currentStep: Int = 0
    private var totalSteps: Int = 0
    private var startValue: Double = 0
    private(set) var targetValue: Double = 0
    private var stepHandler: ((Double, Bool) -> Void)?

    /// True while an animation is in progress.
    var isRunning: Bool { timer != nil }

    /// Cancel any running animation immediately.
    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    /// Animate from `from` to `to` over `duration` seconds using `steps` discrete steps.
    /// `handler(value, isLast)` is called once per step on the main thread.
    /// Calling this cancels any previously running animation.
    func animate(
        from: Double,
        to: Double,
        steps: Int,
        duration: TimeInterval,
        handler: @escaping (Double, Bool) -> Void
    ) {
        cancel()

        // If from ≈ to, no animation needed — just apply final value.
        guard abs(to - from) > 0.001, steps > 1 else {
            handler(to, true)
            return
        }

        let clampedSteps = max(2, steps)
        currentStep = 0
        totalSteps = clampedSteps
        startValue = from
        targetValue = to
        stepHandler = handler
        let interval = duration / Double(clampedSteps)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.currentStep += 1
            let progress = Double(self.currentStep) / Double(self.totalSteps)
            // Ease-out curve: smoother deceleration at the end
            let eased = 1.0 - pow(1.0 - progress, 2.0)
            let value = self.startValue + (self.targetValue - self.startValue) * eased
            let isLast = self.currentStep >= self.totalSteps
            if isLast {
                t.invalidate()
                self.timer = nil
            }
            // Always pass the exact target on the last step to avoid floating-point drift.
            self.stepHandler?(isLast ? self.targetValue : value, isLast)
            if isLast { self.stepHandler = nil }
        }
    }
}

// MARK: - BrightnessService

final class BrightnessService: @unchecked Sendable {
    static let shared = BrightnessService()
    private init() {}

    private let queue = DispatchQueue(label: "com.freedisplay.brightness", qos: .userInitiated)

    // MARK: - Per-display Animators (main thread only)

    /// One animator per display. Accessed only on the main thread.
    private var animators: [CGDirectDisplayID: BrightnessAnimator] = [:]

    private func animator(for displayID: CGDirectDisplayID) -> BrightnessAnimator {
        if let existing = animators[displayID] { return existing }
        let a = BrightnessAnimator()
        animators[displayID] = a
        return a
    }

    /// Cancel any running brightness animation for a display.
    /// Call this before starting an instant (non-animated) change.
    @MainActor
    func cancelAnimation(for displayID: CGDirectDisplayID) {
        animators[displayID]?.cancel()
    }

    // MARK: - Manual Adjust Cooldown

    /// Set when the user manually adjusts brightness; auto-brightness skips updates for 30 s.
    private(set) var lastManualAdjustDate: Date? = nil
    private let manualAdjustLock = NSLock()

    // MARK: - Software Brightness Factors

    /// Stores the current software brightness factor per display (0.05–1.0).
    private var softwareBrightnessFactors: [CGDirectDisplayID: Double] = [:]
    private let softwareBrightnessLock = NSLock()

    /// Keyed by display UUID: CGDirectDisplayIDs change between sessions.
    private func softBrightnessKey(for displayID: CGDirectDisplayID) -> String {
        "fd.softBrightness.\(DisplayInfo.uuid(for: displayID))"
    }

    private func saveSoftwareBrightness(factor: Double, for displayID: CGDirectDisplayID) {
        UserDefaults.standard.set(factor, forKey: softBrightnessKey(for: displayID))
    }

    private func loadSoftwareBrightness(for displayID: CGDirectDisplayID) -> Double? {
        let key = softBrightnessKey(for: displayID)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.double(forKey: key)
    }

    /// Drops factors saved under the old displayID keys (`fd.softBrightness_<id>`), which
    /// could be reapplied to the wrong display in a later session.
    private static let removeLegacySoftBrightnessKeys: Void = {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("fd.softBrightness_") {
            defaults.removeObject(forKey: key)
        }
    }()

    /// Returns the current software brightness factor for a display, or nil if not set.
    func currentSoftwareBrightness(for displayID: CGDirectDisplayID) -> Double? {
        softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] }
    }

    // MARK: - DDC Availability

    /// Tracks whether hardware DDC works for each external display.
    /// nil   = not yet determined
    /// true  = the last DDC read or write succeeded
    /// false = `ddcFailureLimit` operations in a row failed; use software (gamma) fallback
    ///         until the display reconnects or the Mac wakes.
    private var ddcAvailable: [CGDirectDisplayID: Bool] = [:]
    /// Consecutive failed DDC operations (each is already 3 attempts inside DDCService).
    private var ddcFailureCount: [CGDirectDisplayID: Int] = [:]
    private let ddcAvailableLock = NSLock()
    /// Monitors often don't answer right after hot-plug or wake, so one failure isn't enough.
    private static let ddcFailureLimit = 3
    /// Delay between launch/wake DDC probes while a display hasn't answered yet.
    private static let ddcProbeRetryDelay: TimeInterval = 2.0

    /// Per-display DDC max brightness value reported by the monitor.
    /// Used to denormalize 0–100% into the display's native DDC range.
    private var ddcMaxBrightness: [CGDirectDisplayID: UInt16] = [:]

    /// Records a DDC success. Any software dimming left from an earlier fallback is cleared,
    /// otherwise the monitor would be dimmed twice (DDC + gamma).
    private func recordDDCSuccess(for displayID: CGDirectDisplayID, max: UInt16? = nil) {
        ddcAvailableLock.withLock {
            ddcAvailable[displayID] = true
            ddcFailureCount[displayID] = 0
            if let max { ddcMaxBrightness[displayID] = max }
        }
        let hasDimming = softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] != nil }
            || loadSoftwareBrightness(for: displayID) != nil
        if hasDimming {
            DispatchQueue.main.async { [weak self] in self?.clearSoftwareBrightness(for: displayID) }
        }
    }

    /// Records a failed DDC operation. Returns true once the display counts as DDC-unavailable.
    @discardableResult
    private func recordDDCFailure(for displayID: CGDirectDisplayID) -> Bool {
        ddcAvailableLock.withLock {
            let count = (ddcFailureCount[displayID] ?? 0) + 1
            ddcFailureCount[displayID] = count
            if count >= Self.ddcFailureLimit { ddcAvailable[displayID] = false }
            return ddcAvailable[displayID] == false
        }
    }

    /// Forgets DDC availability so every display is probed again. Called on wake.
    func resetDDCState() {
        ddcAvailableLock.withLock {
            ddcAvailable.removeAll()
            ddcFailureCount.removeAll()
        }
        DDCService.shared.clearAllCaches()
    }

    // MARK: - Public API

    /// Reads the display's current brightness into `display.brightness`.
    /// For external displays this is also the DDC probe: if the monitor doesn't answer, it is
    /// retried (monitors are often slow after hot-plug or wake), and once DDC counts as
    /// unavailable the saved software dimming is restored.
    @MainActor
    func refreshBrightness(for display: DisplayInfo) async {
        _ = Self.removeLegacySoftBrightnessKeys
        let isBuiltin = display.isBuiltin
        let displayID = display.displayID

        if isBuiltin {
            let brightness = await withCheckedContinuation { continuation in
                queue.async { [weak self] in
                    continuation.resume(returning: self?.getInternalBrightness())
                }
            }
            if let b = brightness {
                display.brightness = b
            }
        } else {
            // DDC known unavailable: brightness can't be read back; leave the value as-is.
            if isDDCAvailable(for: displayID) == false { return }

            DDCService.shared.readAsync(
                displayID: displayID,
                command: DDCService.brightnessVCP
            ) { [weak self] result in
                guard let self else { return }
                if let result {
                    // DDCService only returns validated replies with max > 0.
                    let brightness = Double(result.current) / Double(result.max) * 100.0
                    self.recordDDCSuccess(for: displayID, max: result.max)
                    Task { @MainActor in display.brightness = brightness }
                } else {
                    let unavailable = self.recordDDCFailure(for: displayID)
                    Task { @MainActor in
                        if unavailable {
                            self.reapplySoftwareBrightnessIfNeeded(for: display)
                        } else {
                            try? await Task.sleep(nanoseconds: UInt64(Self.ddcProbeRetryDelay * 1_000_000_000))
                            await self.refreshBrightness(for: display)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func setBrightness(_ brightness: Double, for display: DisplayInfo, isAutoAdjust: Bool = false) async {
        let clamped = max(0.0, min(100.0, brightness))
        let isBuiltin = display.isBuiltin
        let displayID = display.displayID

        // Record manual adjust time so auto-brightness can honour the cooldown period.
        if !isAutoAdjust {
            manualAdjustLock.withLock { lastManualAdjustDate = Date() }
        }

        // Keep the model in sync for every path (auto-brightness and presets call this too,
        // and brightness keys step from display.brightness), and persist it for the next launch.
        display.brightness = clamped
        SettingsService.shared.setBrightness(clamped, for: displayID)

        if isBuiltin {
            let value = Float(clamped / 100.0)
            queue.async { [weak self] in
                self?.setInternalBrightness(value)
            }
        } else {
            if isDDCAvailable(for: displayID) == false {
                // DDC known unavailable — go straight to software fallback (on the main thread,
                // like every other gamma write, so an older write can't land last).
                setSoftwareBrightness(clamped, for: displayID)
                return
            }

            // Denormalize percentage to display's native DDC range.
            // If max is unknown, default to 100 (safe for most monitors).
            let knownMax: UInt16 = ddcAvailableLock.withLock {
                ddcMaxBrightness[displayID] ?? 100
            }
            let ddcValue = UInt16((clamped / 100.0) * Double(knownMax))

            // Attempt DDC write; if it fails, fall back to gamma table dimming for this change.
            DDCService.shared.writeAsync(
                displayID: displayID,
                command: DDCService.brightnessVCP,
                value: ddcValue
            ) { [weak self] success in
                guard let self else { return }
                if success {
                    self.recordDDCSuccess(for: displayID)
                } else {
                    self.recordDDCFailure(for: displayID)
                    DispatchQueue.main.async { [weak self] in
                        self?.setSoftwareBrightness(clamped, for: displayID)
                    }
                    #if DEBUG
                    print("[BrightnessService] DDC write failed for display \(displayID), using software fallback")
                    #endif
                }
            }
        }
    }

    /// The value brightness is heading to: the running fade's target, else the current value.
    /// Brightness keys step from this so quick presses don't start from mid-fade.
    @MainActor
    func targetBrightness(for display: DisplayInfo) -> Double {
        if let anim = animators[display.displayID], anim.isRunning {
            return anim.targetValue
        }
        return display.brightness
    }

    // MARK: - Smooth Brightness Transitions

    /// Animate brightness from the display's current value to `targetBrightness` smoothly.
    ///
    /// - For DDC displays: sends 5 DDC commands spaced ~40ms apart (200ms total).
    ///   DDC I2C commands are inherently slow (~40–50ms each), so 5 steps at 40ms intervals
    ///   fills the 200ms window without flooding the bus.
    /// - For software (gamma) brightness: 8 gamma table updates over 200ms give a visibly
    ///   smooth fade without perceptible frame drops.
    /// - For built-in displays: 8 writes over 200ms mirror the software path.
    ///
    /// Cancels any previously running animation for the same display, so rapid key presses
    /// always feel responsive — the animation re-targets from wherever it currently is.
    @MainActor
    func setBrightnessSmooth(
        _ targetBrightness: Double,
        for display: DisplayInfo,
        isAutoAdjust: Bool = false
    ) {
        let clamped = max(0.0, min(100.0, targetBrightness))
        let displayID = display.displayID
        let fromBrightness = display.brightness

        if !isAutoAdjust {
            manualAdjustLock.withLock { lastManualAdjustDate = Date() }
        }

        SettingsService.shared.setBrightness(clamped, for: displayID)

        let anim = animator(for: displayID)

        if display.isBuiltin {
            // Built-in: 8 steps over 200ms
            anim.animate(from: fromBrightness, to: clamped, steps: 8, duration: 0.20) { [weak self, weak display] value, _ in
                guard let self, let display else { return }
                display.brightness = value
                let floatVal = Float(value / 100.0)
                self.queue.async { self.setInternalBrightness(floatVal) }
            }
        } else if isDDCAvailable(for: displayID) == false {
            // Software (gamma) path: 8 steps over 200ms
            anim.animate(from: fromBrightness, to: clamped, steps: 8, duration: 0.20) { [weak display] value, _ in
                display?.brightness = value
                BrightnessService.shared.setSoftwareBrightness(value, for: displayID)
            }
        } else {
            // DDC path: 5 steps over 200ms.
            // DDC I2C is slow (~40-50ms per command), so 5 steps at 40ms intervals
            // keeps the bus from overloading while giving smooth visible steps.
            let knownMax: UInt16 = ddcAvailableLock.withLock {
                ddcMaxBrightness[displayID] ?? 100
            }
            anim.animate(from: fromBrightness, to: clamped, steps: 5, duration: 0.20) { [weak self, weak display] value, isLast in
                guard let self else { return }
                display?.brightness = value
                let ddcValue = UInt16((value / 100.0) * Double(knownMax))
                DDCService.shared.writeAsync(
                    displayID: displayID,
                    command: DDCService.brightnessVCP,
                    value: ddcValue
                ) { [weak self] success in
                    guard let self else { return }
                    if success {
                        self.recordDDCSuccess(for: displayID)
                    } else if isLast {
                        // Only the final step counts; fall back to software for this change.
                        self.recordDDCFailure(for: displayID)
                        DispatchQueue.main.async { [weak self] in
                            self?.setSoftwareBrightness(clamped, for: displayID)
                        }
                        #if DEBUG
                        print("[BrightnessService] smooth DDC failed for \(displayID), using software fallback")
                        #endif
                    }
                }
            }
        }
    }

    // MARK: - Software Brightness (Gamma Table Fallback)

    /// Dims a display through its gamma table, for displays where DDC is unavailable.
    /// brightness: 0–100 (percentage); never goes below 5% to avoid a completely black screen.
    /// GammaService writes the table (it is the only gamma writer) and combines the factor
    /// with any image adjustment. Main thread only.
    func setSoftwareBrightness(_ brightness: Double, for displayID: CGDirectDisplayID) {
        let factor = max(0.05, brightness / 100.0)
        softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] = factor }
        saveSoftwareBrightness(factor: factor, for: displayID)
        GammaService.shared.refresh(for: displayID)
        #if DEBUG
        print("[BrightnessService] software brightness set to \(Int(brightness))% for display \(displayID)")
        #endif
    }

    /// Removes software dimming for a display (in memory and saved). Main thread only.
    func clearSoftwareBrightness(for displayID: CGDirectDisplayID) {
        softwareBrightnessLock.withLock { _ = softwareBrightnessFactors.removeValue(forKey: displayID) }
        UserDefaults.standard.removeObject(forKey: softBrightnessKey(for: displayID))
        GammaService.shared.refresh(for: displayID)
    }

    /// Returns whether DDC is available for the given display.
    /// nil means not yet determined (first use).
    func isDDCAvailable(for displayID: CGDirectDisplayID) -> Bool? {
        ddcAvailableLock.withLock { ddcAvailable[displayID] }
    }

    /// Clears DDC availability and max brightness cache for a disconnected display.
    /// Call this when a display is removed so stale state cannot pollute a reconnect.
    func invalidateDDCState(for displayID: CGDirectDisplayID) {
        ddcAvailableLock.withLock {
            ddcAvailable.removeValue(forKey: displayID)
            ddcFailureCount.removeValue(forKey: displayID)
            ddcMaxBrightness.removeValue(forKey: displayID)
        }
    }

    /// Restores the saved software dimming for an external display that doesn't support DDC.
    /// Called once DDC counts as unavailable. Checks in-memory factor first; falls back to
    /// UserDefaults so restart is handled too. No-op if no saved factor < 1.0 exists.
    func reapplySoftwareBrightnessIfNeeded(for display: DisplayInfo) {
        let displayID = display.displayID
        guard isDDCAvailable(for: displayID) == false else { return }
        let inMemory = softwareBrightnessLock.withLock { softwareBrightnessFactors[displayID] }
        let factor = inMemory ?? loadSoftwareBrightness(for: displayID)
        guard let f = factor, f < 1.0 else { return }
        setSoftwareBrightness(f * 100.0, for: displayID)
        // Show the dimming level on the slider.
        DispatchQueue.main.async { display.brightness = f * 100.0 }
    }

    // MARK: - Internal Display (DisplayServices, IODisplayGetFloatParameter fallback)

    private static nonisolated(unsafe) let ioDisplayBrightnessKey = "brightness" as CFString

    /// The online built-in display's ID, or nil (no built-in display, or lid closed).
    private func builtinDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)
        return (0..<Int(displayCount))
            .map({ displayIDs[$0] })
            .first(where: { CGDisplayIsBuiltin($0) != 0 })
    }

    /// Returns the io_service_t for the built-in display using CGDisplayIOServicePort.
    /// Only works on Intel Macs; on Apple Silicon the port is always 0.
    /// Caller does NOT need to release — CGDisplayIOServicePort returns a non-retained port.
    private func builtinIOService() -> io_service_t? {
        guard let builtinID = builtinDisplayID() else { return nil }

        // CGDisplayIOServicePort returns a non-retained service port (do not release)
        let servicePort = CGDisplayIOServicePort(builtinID)
        if servicePort != MACH_PORT_NULL && servicePort != 0 {
            return servicePort
        }

        return nil
    }

    private func getInternalBrightness() -> Double? {
        // Primary: DisplayServices (works on Apple Silicon).
        if let builtinID = builtinDisplayID(),
           let value = displayServicesBrightness(for: builtinID) {
            return value * 100.0
        }

        // Intel fallback: use CGDisplayIOServicePort to get the specific builtin display service
        if let servicePort = builtinIOService() {
            var value: Float = 0
            if IODisplayGetFloatParameter(
                servicePort, 0, Self.ioDisplayBrightnessKey, &value
            ) == KERN_SUCCESS {
                return Double(value) * 100.0
            }
        }

        // Fallback: iterate IODisplayConnect but only accept services that
        // correspond to a built-in display (matched via CGDisplayIOServicePort cross-check).
        // Build set of known external service ports to exclude them.
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        var externalPorts = Set<io_service_t>()
        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            if CGDisplayIsBuiltin(id) == 0 {
                let port = CGDisplayIOServicePort(id)
                if port != MACH_PORT_NULL && port != 0 {
                    externalPorts.insert(port)
                }
            }
        }

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iter
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            // Skip services that are known external display ports
            guard !externalPorts.contains(service) else { continue }
            var value: Float = 0
            if IODisplayGetFloatParameter(
                service, 0, Self.ioDisplayBrightnessKey, &value
            ) == KERN_SUCCESS {
                return Double(value) * 100.0
            }
        }
        return nil
    }

    private func setInternalBrightness(_ value: Float) {
        // Primary: DisplayServices (works on Apple Silicon).
        if let builtinID = builtinDisplayID(),
           setDisplayServicesBrightness(Double(value), for: builtinID) {
            #if DEBUG
            print("[BrightnessService] internal brightness set to \(value) via DisplayServices")
            #endif
            return
        }

        // Intel fallback: use CGDisplayIOServicePort to target only the builtin display service
        if let servicePort = builtinIOService() {
            if IODisplaySetFloatParameter(
                servicePort, 0, Self.ioDisplayBrightnessKey, value
            ) == KERN_SUCCESS {
                #if DEBUG
                print("[BrightnessService] internal brightness set to \(value)")
                #endif
                return
            }
        }

        // Fallback: iterate IODisplayConnect, skipping known external ports
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        var externalPorts = Set<io_service_t>()
        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            if CGDisplayIsBuiltin(id) == 0 {
                let port = CGDisplayIOServicePort(id)
                if port != MACH_PORT_NULL && port != 0 {
                    externalPorts.insert(port)
                }
            }
        }

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iter
        ) == KERN_SUCCESS else {
            #if DEBUG
            print("[BrightnessService] setInternalBrightness: no builtin service responded")
            #endif
            return
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
            guard !externalPorts.contains(service) else { continue }
            if IODisplaySetFloatParameter(
                service, 0, Self.ioDisplayBrightnessKey, value
            ) == KERN_SUCCESS {
                #if DEBUG
                print("[BrightnessService] internal brightness set to \(value)")
                #endif
                return
            }
        }
        #if DEBUG
        print("[BrightnessService] setInternalBrightness: no builtin service responded")
        #endif
    }
}
