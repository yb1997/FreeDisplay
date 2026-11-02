import AppKit
import CoreGraphics
@preconcurrency import ColorSync

/// Per-display software image adjustment parameters.
/// All slider values are in the range -100...+100 with 0 = neutral,
/// except quantizationLevels (2...256, 256 = no quantization).
struct GammaAdjustment {
    var contrast: Double = 0.0          // -100 to +100, 0 = neutral
    var gammaVal: Double = 0.0          // -100 to +100, 0 = neutral (gamma exponent 1.0)
    var gain: Double = 0.0              // -100 to +100, 0 = neutral (multiplier 1.0)
    var colorTemperature: Double = 0.0  // -100 to +100, 0 = neutral (6500 K)
    var rGamma: Double = 0.0            // per-channel gamma offset
    var gGamma: Double = 0.0
    var bGamma: Double = 0.0
    var rGain: Double = 0.0             // per-channel gain offset
    var gGain: Double = 0.0
    var bGain: Double = 0.0
    var quantizationLevels: Int = 256   // 256 = no quantization
    var isInverted: Bool = false
    var isPaused: Bool = false

    /// True when every value is at its default, so the adjustment changes nothing.
    var isNeutral: Bool {
        contrast == 0 && gammaVal == 0 && gain == 0 && colorTemperature == 0 &&
        rGamma == 0 && gGamma == 0 && bGamma == 0 && rGain == 0 && gGain == 0 && bGain == 0 &&
        quantizationLevels >= 256 && !isInverted
    }
}

/// The single writer of display transfer (gamma) tables.
/// The final table for a display combines the image adjustment (if one is active) with the
/// software brightness factor from BrightnessService, so the two never overwrite each other.
/// With neither active, the display's own color profile curve is restored.
final class GammaService: @unchecked Sendable {
    static let shared = GammaService()
    private var terminateObserver: NSObjectProtocol?
    private let adjustmentsLock = NSLock()

    private init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let touched = self.adjustmentsLock.withLock { self.touchedDisplays }
            for displayID in touched { self.restoreProfileCurve(for: displayID) }
        }
    }

    deinit {
        if let obs = terminateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - State

    /// Most recently applied adjustment per display (paused ones are kept so they can resume).
    private var activeAdjustments: [CGDirectDisplayID: GammaAdjustment] = [:]
    /// Displays whose table this service has written, so quitting only restores those.
    private var touchedDisplays: Set<CGDirectDisplayID> = []

    // MARK: - Public API

    /// Apply a complete GammaAdjustment snapshot to the given display.
    func apply(_ adj: GammaAdjustment, for displayID: CGDirectDisplayID) {
        guard !adj.isPaused else { return }
        adjustmentsLock.withLock { activeAdjustments[displayID] = adj }
        refresh(for: displayID)
    }

    /// Re-writes the display's table from the current adjustment and software brightness.
    /// BrightnessService calls this after changing the software brightness factor.
    func refresh(for displayID: CGDirectDisplayID) {
        let adj = adjustmentsLock.withLock { activeAdjustments[displayID] }
        let activeAdj = (adj.map { !$0.isPaused && !$0.isNeutral } == true) ? adj : nil
        let factor = BrightnessService.shared.currentSoftwareBrightness(for: displayID) ?? 1.0

        if activeAdj == nil && factor >= 1.0 {
            // Nothing to apply. Only restore displays we changed; leave the rest alone.
            let wasTouched = adjustmentsLock.withLock { touchedDisplays.remove(displayID) != nil }
            if wasTouched { restoreProfileCurve(for: displayID) }
            return
        }
        writeTable(adj: activeAdj, factor: max(0.05, factor), for: displayID)
    }

    /// "Pause": stop showing the adjustment without discarding it. Software dimming stays.
    func pause(for displayID: CGDirectDisplayID) {
        adjustmentsLock.withLock {
            if var adj = activeAdjustments[displayID] {
                adj.isPaused = true
                activeAdjustments[displayID] = adj
            }
        }
        refresh(for: displayID)
    }

    /// Removes the image adjustment for one display. Software dimming and the
    /// assigned color profile are kept.
    func resetAdjustment(for displayID: CGDirectDisplayID) {
        adjustmentsLock.withLock { _ = activeAdjustments.removeValue(forKey: displayID) }
        refresh(for: displayID)
    }

    /// Restores the display's color profile curve (including any calibration it carries)
    /// by re-assigning its current profile: the custom one if set, otherwise the factory one.
    /// Per display, unlike the global CGDisplayRestoreColorSyncSettings().
    private func restoreProfileCurve(for displayID: CGDirectDisplayID) {
        guard let rawUUID = CGDisplayCreateUUIDFromDisplayID(displayID),
              let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
              let profileIDKey = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue()
        else { return }
        let uuid = rawUUID.takeRetainedValue()
        var profile: Any = NSNull()  // NSNull = no custom profile, use the factory one
        if let rawInfo = ColorSyncDeviceCopyDeviceInfo(deviceClass, uuid) {
            let info = rawInfo.takeRetainedValue() as NSDictionary
            // Same lookup as ColorProfileService.currentProfileURL: CustomProfiles is keyed by
            // the active mode name found at FactoryProfiles[DeviceDefaultProfileID] (e.g. "1").
            let activeMode = (info["FactoryProfiles"] as? NSDictionary)?[profileIDKey]
            if let custom = info["CustomProfiles"] as? NSDictionary,
               let current = activeMode.flatMap({ custom[$0] }) ?? custom.allValues.first {
                profile = current
            }
        }
        ColorSyncDeviceSetCustomProfiles(deviceClass, uuid, [profileIDKey: profile] as CFDictionary)
    }

    // MARK: - Persistence (keyed by display UUID; CGDirectDisplayIDs change between sessions)

    private static func stateKey(for displayID: CGDirectDisplayID) -> String {
        "fd.GammaService.savedAdjustment.\(DisplayInfo.uuid(for: displayID))"
    }

    private static func legacyStateKey(for displayID: CGDirectDisplayID) -> String {
        "fd.GammaService.savedAdjustment.\(displayID)"
    }

    func saveState(_ adj: GammaAdjustment, for displayID: CGDirectDisplayID) {
        let dict: [String: Any] = [
            "contrast": adj.contrast,
            "gammaVal": adj.gammaVal,
            "gain": adj.gain,
            "colorTemperature": adj.colorTemperature,
            "rGamma": adj.rGamma, "gGamma": adj.gGamma, "bGamma": adj.bGamma,
            "rGain": adj.rGain,   "gGain": adj.gGain,   "bGain": adj.bGain,
            "quantizationLevels": adj.quantizationLevels,
            "isInverted": adj.isInverted,
            "isPaused": adj.isPaused
        ]
        UserDefaults.standard.set(dict, forKey: GammaService.stateKey(for: displayID))
    }

    func loadSavedState(for displayID: CGDirectDisplayID) -> GammaAdjustment? {
        let defaults = UserDefaults.standard
        var dict = defaults.dictionary(forKey: GammaService.stateKey(for: displayID))
        if dict == nil, let legacy = defaults.dictionary(forKey: GammaService.legacyStateKey(for: displayID)) {
            // Migrate a value saved under the old displayID key.
            defaults.set(legacy, forKey: GammaService.stateKey(for: displayID))
            defaults.removeObject(forKey: GammaService.legacyStateKey(for: displayID))
            dict = legacy
        }
        guard let dict else { return nil }
        var adj = GammaAdjustment()
        adj.contrast           = dict["contrast"]           as? Double ?? 0
        adj.gammaVal           = dict["gammaVal"]           as? Double ?? 0
        adj.gain               = dict["gain"]               as? Double ?? 0
        adj.colorTemperature   = dict["colorTemperature"]   as? Double ?? 0
        adj.rGamma             = dict["rGamma"]             as? Double ?? 0
        adj.gGamma             = dict["gGamma"]             as? Double ?? 0
        adj.bGamma             = dict["bGamma"]             as? Double ?? 0
        adj.rGain              = dict["rGain"]              as? Double ?? 0
        adj.gGain              = dict["gGain"]              as? Double ?? 0
        adj.bGain              = dict["bGain"]              as? Double ?? 0
        adj.quantizationLevels = dict["quantizationLevels"] as? Int    ?? 256
        adj.isInverted         = dict["isInverted"]         as? Bool   ?? false
        adj.isPaused           = dict["isPaused"]           as? Bool   ?? false
        return adj
    }

    func clearSavedState(for displayID: CGDirectDisplayID) {
        UserDefaults.standard.removeObject(forKey: GammaService.stateKey(for: displayID))
        UserDefaults.standard.removeObject(forKey: GammaService.legacyStateKey(for: displayID))
    }

    /// Re-applies the persisted adjustment and current software brightness for a display
    /// (e.g. after wake from sleep or display reconnect).
    func reapplyIfNeeded(for displayID: CGDirectDisplayID) {
        if let adj = loadSavedState(for: displayID) {
            adjustmentsLock.withLock { activeAdjustments[displayID] = adj }
        }
        refresh(for: displayID)
    }

    // MARK: - Table

    /// Builds and writes the 256-entry table. Per channel and input x:
    ///   gamma → gain × color temperature → contrast (stretch around 0.5) → invert → clamp
    ///   → quantize → × software brightness factor.
    /// Positive gain and contrast push values past 1 and are then clipped, so they now
    /// brighten / stretch instead of being clamped away; every value is clamped to 0–1.
    private func writeTable(adj: GammaAdjustment?, factor: Double, for displayID: CGDirectDisplayID) {
        let a = adj ?? GammaAdjustment()
        let p = channelParams(for: a)
        // Contrast slider -100…+100 → slope 0.2…2.0 around mid-grey (0 → 1.0).
        let c = a.contrast / 100.0
        let slope = c >= 0 ? 1.0 + c : 1.0 + 0.8 * c
        let levels = max(2, min(256, a.quantizationLevels))

        let size = 256
        func channel(gamma: Double, scale: Double) -> [CGGammaValue] {
            (0..<size).map { i in
                let x = Double(i) / Double(size - 1)
                var v = pow(x, gamma) * scale
                v = 0.5 + (v - 0.5) * slope
                v = max(0.0, min(1.0, v))
                if a.isInverted { v = 1.0 - v }
                if levels < 256 {
                    v = (v * Double(levels - 1)).rounded() / Double(levels - 1)
                }
                return CGGammaValue(v * factor)
            }
        }
        var red   = channel(gamma: p.rGam, scale: p.rScale)
        var green = channel(gamma: p.gGam, scale: p.gScale)
        var blue  = channel(gamma: p.bGam, scale: p.bScale)

        adjustmentsLock.withLock { _ = touchedDisplays.insert(displayID) }
        let result = CGSetDisplayTransferByTable(displayID, UInt32(size), &red, &green, &blue)
        #if DEBUG
        if result != .success {
            print("[GammaService] CGSetDisplayTransferByTable failed: \(result)")
        }
        #endif
    }

    private struct ChannelParams {
        var rScale, rGam: Double
        var gScale, gGam: Double
        var bScale, bGam: Double
    }

    private func channelParams(for adj: GammaAdjustment) -> ChannelParams {
        // ── Gamma exponent ──────────────────────────────────────────────
        // slider=0 → exp=1.0; +100 → 0.5 (brighter curve); -100 → 2.0 (darker)
        let globalGammaExp = pow(2.0, -adj.gammaVal / 100.0)
        let rGammaExp = globalGammaExp * pow(2.0, -adj.rGamma / 100.0)
        let gGammaExp = globalGammaExp * pow(2.0, -adj.gGamma / 100.0)
        let bGammaExp = globalGammaExp * pow(2.0, -adj.bGamma / 100.0)

        // ── Gain (output scale) ─────────────────────────────────────────
        // slider=0 → 1.0; +100 → 2.0; -100 → 0.0
        let globalGain = max(0.0, 1.0 + adj.gain / 100.0)
        let rGain = max(0.0, globalGain * (1.0 + adj.rGain / 100.0))
        let gGain = max(0.0, globalGain * (1.0 + adj.gGain / 100.0))
        let bGain = max(0.0, globalGain * (1.0 + adj.bGain / 100.0))

        // ── Color temperature ───────────────────────────────────────────
        let (tempR, tempG, tempB) = colorTempFactors(adj.colorTemperature)

        return ChannelParams(
            rScale: rGain * tempR, rGam: rGammaExp,
            gScale: gGain * tempG, gGam: gGammaExp,
            bScale: bGain * tempB, bGam: bGammaExp)
    }

    // MARK: - Color temperature (Tanner Helland algorithm)

    /// Returns per-channel gain multipliers normalised so that 6500 K → (1, 1, 1).
    private func colorTempFactors(_ sliderValue: Double) -> (r: Double, g: Double, b: Double) {
        guard sliderValue != 0.0 else { return (1.0, 1.0, 1.0) }
        // positive slider = warmer (lower K); negative = cooler (higher K)
        let kelvin: Double
        if sliderValue > 0 {
            kelvin = 6500.0 - sliderValue / 100.0 * 4500.0  // 6500 K → 2000 K
        } else {
            kelvin = 6500.0 - sliderValue / 100.0 * 5500.0  // 6500 K → 12000 K
        }
        let (r, g, b) = kelvinToRGB(kelvin)
        let (rN, gN, bN) = kelvinToRGB(6500.0)
        return (
            rN > 0 ? r / rN : r,
            gN > 0 ? g / gN : g,
            bN > 0 ? b / bN : b
        )
    }

    private func kelvinToRGB(_ kelvin: Double) -> (Double, Double, Double) {
        let temp = max(1000.0, min(40000.0, kelvin)) / 100.0

        let r: Double
        if temp <= 66 {
            r = 1.0
        } else {
            r = max(0, min(1, 1.292936186 * pow(temp - 60, -0.1332047592)))
        }

        let g: Double
        if temp <= 66 {
            g = max(0, min(1, 0.390081579 * log(temp) - 0.631841444))
        } else {
            g = max(0, min(1, 1.129890861 * pow(temp - 60, -0.0755148492)))
        }

        let b: Double
        if temp >= 66 {
            b = 1.0
        } else if temp <= 19 {
            b = 0.0
        } else {
            b = max(0, min(1, 0.543206789 * log(temp - 10) - 1.196254089))
        }

        return (r, g, b)
    }
}
