import Foundation
import AppKit
import CoreGraphics

// Global C-compatible callback for display reconfiguration.
// Must be a top-level function (not a closure) to be used as a C function pointer.
private func displayReconfigCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let ptr = userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(ptr).takeUnretainedValue()

    let relevant: CGDisplayChangeSummaryFlags = [.addFlag, .removeFlag, .setMainFlag, .setModeFlag, .movedFlag]
    guard !flags.intersection(relevant).isEmpty else { return }

    // Skip the begin-configuration notification; only act when the change is complete.
    // (beginConfigurationFlag is set at the start of a transaction; absence means it finished.)
    guard !flags.contains(.beginConfigurationFlag) else { return }

    Task { @MainActor in
        if flags.intersection([.addFlag, .removeFlag]).isEmpty {
            // Mode, main-display or position change: refresh existing displays only.
            manager.refreshExistingDisplayModes()
            if flags.contains(.setModeFlag) {
                // Follow resolution changes made outside FreeDisplay (System Settings etc.).
                ResolutionService.shared.noteModeChanged(for: displayID)
            }
        } else {
            manager.refreshDisplays()
        }

        // Auto-rearrange after display config changes (debounced 500 ms), but not for
        // move-only events: those come from the user dragging in System Settings, or from
        // the auto-arrange itself, and must not be snapped back.
        if !flags.intersection([.addFlag, .removeFlag, .setMainFlag, .setModeFlag]).isEmpty {
            manager.scheduleAutoArrange()
        }
    }
}

@MainActor
class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []

    // nonisolated(unsafe) allows deinit (which is nonisolated in Swift 6) to access this value.
    nonisolated(unsafe) private var callbackContext: UnsafeMutableRawPointer?

    /// Work item used to debounce auto-arrange calls triggered by display config changes.
    private var autoArrangeWorkItem: DispatchWorkItem?

    nonisolated(unsafe) private var sleepObservers: [NSObjectProtocol] = []

    init() {
        refreshDisplays()
        setupReconfigCallback()
        setupSleepWakeObservers()
    }

    deinit {
        if let ctx = callbackContext {
            CGDisplayRemoveReconfigurationCallback(displayReconfigCallback, ctx)
            Unmanaged<DisplayManager>.fromOpaque(ctx).release()
        }
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// Registered here (not in the menu's `.task`, which only runs once the menu is opened)
    /// so wake re-apply works from launch.
    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            // macOS resets display modes around sleep; don't record those as user changes.
            Task { @MainActor in ResolutionService.shared.beginSleepSuppression() }
        })
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
    }

    private func handleWake() {
        ResolutionService.shared.beginSleepSuppression()
        Task { @MainActor in
            // Give WindowServer 2 seconds to stabilize after wake before touching display state.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            refreshDisplays()
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Monitors may answer DDC differently after wake: probe every external display
            // again. A display that still doesn't answer gets its software dimming back
            // (BrightnessService.refreshBrightness handles that).
            BrightnessService.shared.resetDDCState()
            for display in displays {
                // The in-memory software brightness factor is included by GammaService.
                GammaService.shared.reapplyIfNeeded(for: display.displayID)
                if !display.isBuiltin {
                    Task { await BrightnessService.shared.refreshBrightness(for: display) }
                }
                // Re-apply any custom resolution that macOS may have reset on wake
                ResolutionService.shared.reapplySavedModeIfNeeded(for: display.displayID)
            }
            ResolutionService.shared.endSleepSuppression()
        }
    }

    func refreshDisplays() {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        let currentIDs = Set(displays.map { $0.displayID })
        let newIDSet = Set((0..<Int(displayCount)).map { displayIDs[$0] })

        // Clean up DDC cache for removed displays to prevent stale entries accumulating
        let removedIDs = currentIDs.subtracting(newIDSet)
        removedIDs.forEach {
            DDCService.shared.clearCache(for: $0)
            BrightnessService.shared.invalidateDDCState(for: $0)
        }

        // Diff-based refresh: keep existing DisplayInfo objects (preserves @Published state)
        var existingByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.displayID, $0) })

        var updatedDisplays: [DisplayInfo] = []
        var addedDisplays: [DisplayInfo] = []

        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            if let existing = existingByID[id] {
                updatedDisplays.append(existing)
            } else {
                let info = DisplayInfo(displayID: id)
                updatedDisplays.append(info)
                addedDisplays.append(info)
            }
        }

        displays = updatedDisplays
        DisplayManagerAccessor.shared.displays = updatedDisplays

        // Regenerate built-in presets (HiDPI Mode / Native Mode) from updated display list.
        PresetService.shared.refreshBuiltins()

        // Only load details / refresh brightness for newly appeared displays
        for display in addedDisplays {
            Task { await BrightnessService.shared.refreshBrightness(for: display) }
            Task {
                await display.loadDetails()
                // Auto-enable HiDPI for new external 2K+ displays that don't have it yet
                if !display.isBuiltin {
                    await self.autoEnableHiDPIIfNeeded(for: display)
                }
                PresetService.shared.refreshBuiltins()
            }
            // Restore the saved image adjustment for the reconnected display. Saved software
            // dimming is restored by refreshBrightness once DDC turns out to be unavailable.
            // Brief delay lets WindowServer settle before we write transfer tables.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                GammaService.shared.reapplyIfNeeded(for: display.displayID)
            }
        }

        // For displays that were already present, only update bounds/main flag (no DDC probe).
        let keptIDs = currentIDs.intersection(newIDSet)
        for display in updatedDisplays where keptIDs.contains(display.displayID) {
            display.bounds = CGDisplayBounds(display.displayID)
            display.isMain = CGDisplayIsMain(display.displayID) != 0
        }
    }

    /// True while the HiDPI offer is on screen, so two new displays don't stack alerts.
    private var isOfferingHiDPI = false

    /// Offers to enable the HiDPI plist override for external 2K+ displays that don't have it.
    /// The user is asked first (it needs an administrator password); declining, canceling the
    /// password prompt or later turning HiDPI off opts that monitor model out for good.
    private func autoEnableHiDPIIfNeeded(for display: DisplayInfo) async {
        let vendor = display.vendorNumber
        let product = display.modelNumber
        guard vendor != 0, product != 0,
              CGDisplayVendorNumber(display.displayID) != VirtualDisplayService.virtualVendorID else { return }

        // Already enabled, or the user said no before — nothing to do
        guard !HiDPIService.shared.isHiDPIEnabled(vendor: vendor, product: product),
              !HiDPIService.shared.isAutoEnableOptedOut(vendor: vendor, product: product) else { return }

        // Determine native resolution from available modes
        let (nativeW, nativeH) = display.nativeResolution

        // Only offer for 2K+ displays (width >= 2560 or total pixels >= 2560*1440)
        guard nativeW >= 2560 || (nativeW * nativeH >= 2560 * 1440) else { return }

        // Ask once launch/hot-plug setup has settled, one display at a time.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !isOfferingHiDPI, displays.contains(where: { $0 === display }) else { return }
        isOfferingHiDPI = true
        defer { isOfferingHiDPI = false }

        let alert = NSAlert()
        alert.messageText = String(localized: "Turn on HiDPI for \(display.name)?")
        alert.informativeText = String(localized: "HiDPI makes text and images sharper on this display. Turning it on needs your administrator password once, and the display may need to be reconnected. You can change this later in the display’s HiDPI section.")
        alert.addButton(withTitle: String(localized: "Turn On HiDPI"))
        alert.addButton(withTitle: String(localized: "Not for This Display"))
        // A menu-bar-only app must come forward, or the alert opens behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            HiDPIService.shared.setAutoEnableOptedOut(true, vendor: vendor, product: product)
            return
        }

        print("[DisplayManager] Enabling HiDPI for \(display.name) (\(nativeW)×\(nativeH), vendor=\(vendor), product=\(product))")

        let err = await HiDPIService.shared.enableHiDPI(
            for: display.displayID,
            vendor: vendor,
            product: product,
            nativeWidth: nativeW,
            nativeHeight: nativeH
        )

        if let err {
            print("[DisplayManager] Auto-enable HiDPI failed: \(err)")
            if err == HiDPIService.authorizationCanceledMessage {
                HiDPIService.shared.setAutoEnableOptedOut(true, vendor: vendor, product: product)
            }
        } else {
            print("[DisplayManager] Auto-enable HiDPI succeeded, refreshing modes")
            HiDPIService.shared.refreshModes(for: display)
            // Give IOServiceRequestProbe time to re-enumerate modes
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await display.loadDetails()
            PresetService.shared.refreshBuiltins()
        }
    }

    /// Debounces calls to `arrangeExternalAboveBuiltin()` — coalesces bursts of config-change
    /// callbacks into a single rearrange that fires 500 ms after the last callback arrives.
    func scheduleAutoArrange() {
        autoArrangeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.arrangeExternalAboveBuiltin()
        }
        autoArrangeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func setupReconfigCallback() {
        let ctx = Unmanaged.passRetained(self).toOpaque()
        callbackContext = ctx
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, ctx)
    }

    /// Refreshes mode info, bounds, size and main-display flag for already-tracked displays
    /// (for setModeFlag / setMainFlag / movedFlag events).
    /// Cheaper than a full `refreshDisplays()` — does not add/remove DisplayInfo objects.
    func refreshExistingDisplayModes() {
        for display in displays {
            // Cheap synchronous reads; arrangement, auto-arrange and presets rely on them.
            // macOS sends one callback per display for a single change, so only assign what
            // changed: every @Published assignment re-renders the views observing the display.
            let id = display.displayID
            let isMain = CGDisplayIsMain(id) != 0
            if display.isMain != isMain { display.isMain = isMain }
            let bounds = CGDisplayBounds(id)
            if display.bounds != bounds { display.bounds = bounds }
            let pixelWidth = CGDisplayPixelsWide(id)
            if display.pixelWidth != pixelWidth { display.pixelWidth = pixelWidth }
            let pixelHeight = CGDisplayPixelsHigh(id)
            if display.pixelHeight != pixelHeight { display.pixelHeight = pixelHeight }
            let mode = DisplayMode.currentMode(for: id)
            if display.currentDisplayMode != mode { display.currentDisplayMode = mode }
        }
    }

    /// Toggle a display on/off.
    /// NOTE: macOS has no public API for enabling/disabling individual displays
    /// (CGConfigureDisplayEnabled is private). This function always returns false
    /// to signal to callers that the operation is not supported.
    @discardableResult
    func toggleDisplay(_ display: DisplayInfo) -> Bool {
        // No-op: cannot enable/disable displays via public API
        return false
    }

    /// Makes the target display the main display by shifting the whole layout so it sits at (0, 0).
    @discardableResult
    func setAsMainDisplay(_ display: DisplayInfo) async -> Bool {
        let ok = await ArrangementService.shared.setAsMainDisplay(display.displayID)
        if ok { refreshDisplays() }
        return ok
    }

    /// Positions all external displays above the built-in display, centered horizontally.
    /// Controlled by the UserDefaults key `fd.arrangement.externalAbove`.
    /// Does nothing if there is no built-in display or no external displays.
    func arrangeExternalAboveBuiltin() {
        guard UserDefaults.standard.bool(forKey: "fd.arrangement.externalAbove") else { return }

        guard let builtin = displays.first(where: { $0.isBuiltin }) else { return }
        // Skip virtual displays FreeDisplay created; they aren't monitors to arrange.
        let externals = displays
            .filter { !$0.isBuiltin && CGDisplayVendorNumber($0.displayID) != VirtualDisplayService.virtualVendorID }
            .sorted { CGDisplayBounds($0.displayID).origin.x < CGDisplayBounds($1.displayID).origin.x }
        guard !externals.isEmpty else { return }

        // Read live bounds: DisplayInfo.bounds can lag behind a change still being processed.
        let builtinBounds = CGDisplayBounds(builtin.displayID)
        let sizes = externals.map { CGDisplayBounds($0.displayID).size }
        let totalWidth = Int(sizes.reduce(0) { $0 + $1.width })

        // Lay all externals side by side as one group, centered above the built-in display,
        // bottoms aligned to its top edge.
        var x = Int(builtinBounds.midX) - totalWidth / 2
        var items: [(id: CGDirectDisplayID, x: Int, y: Int)] = []
        for (ext, size) in zip(externals, sizes) {
            items.append((id: ext.displayID, x: x, y: Int(builtinBounds.minY) - Int(size.height)))
            x += Int(size.width)
        }

        // Already in place: don't reconfigure (the reconfiguration callback would schedule
        // this again after our own change).
        let alreadyPlaced = items.allSatisfy { item in
            let origin = CGDisplayBounds(item.id).origin
            return Int(origin.x) == item.x && Int(origin.y) == item.y
        }
        guard !alreadyPlaced else { return }

        Task { @MainActor in
            if await ArrangementService.shared.setOrigins(items) {
                self.refreshDisplays()
            }
        }
    }
}
