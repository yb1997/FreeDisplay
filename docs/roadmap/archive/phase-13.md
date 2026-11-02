# Phase 13: Critical bug fixes

> Goal: fix three functional bugs reported by the user

## Task list

- [x] Fix the lingering image after image adjustments are closed
  - Implementation hints:
    1. Add `.onDisappear` to `ImageAdjustmentView.swift`: check whether every slider is at zero, and if not, call `GammaService.shared.restoreColorSync()`
    2. In the `init()` of `GammaService.swift`, register an observer for `NSApplication.willTerminateNotification` whose callback calls `CGDisplayRestoreColorSyncSettings()`
    3. Add a backup in `applicationWillTerminate` of `AppDelegate.swift` as well: `CGDisplayRestoreColorSyncSettings()`
    4. Consider adding `saveState()` / `restoreState()` methods to GammaService that save the current adjustment values to UserDefaults in onDisappear and restore them in onAppear (so closing the panel doesn't lose the settings, but quitting the app cleans up completely)
  - Verification: adjust the gamma → collapse the image adjustments panel → the screen returns to normal; force-quit the app → the screen returns to normal

- [x] Fix the 1920x1080 resolution not being clickable
  - Implementation hints:
    1. In the `switchTo()` method of `DisplayModeListView.swift`: remove the silent `mode.id != display.currentDisplayMode?.id` guard, and instead, if it's the current mode, show an "Already the current mode" hint (flash the highlight with `withAnimation`)
    2. Change the `ResolutionService.shared.setDisplayMode()` call to `Task { @MainActor in }`, setting `isSwitching = true` before the call and `isSwitching = false` after the await completes
    3. Change `setDisplayMode` in `ResolutionService.swift` to an `async` method that wraps `CGConfigureDisplayWithDisplayMode` + `CGCompleteDisplayConfiguration` in `withCheckedContinuation`
    4. Add failure feedback: if `setDisplayMode` returns false, show an error hint
  - Verification: click 1920x1080 → loading shows → it switches successfully or shows an error message; click the mode that's already current → "Already the current mode" shows

- [x] Fix HiDPI scaled modes not showing/requiring a reconnect
  - Implementation hints:
    1. After `enableHiDPI()` in `HiDPIService.swift` finishes writing the plist, call `CGDisplayForceToMirror(displayID, 0)` and then `CGDisplayForceToMirror(displayID, kCGNullDirectDisplay)` to make the display re-enumerate its modes (following BetterDisplay's approach)
    2. If that method isn't available, the alternative: use `IOServiceRequestProbe` to tell IOKit to rescan
    3. After refreshing, call `DisplayMode.availableModes(for:)` to get the mode list again and update `display.availableModes`
    4. Add a "Refresh mode list" button to `DisplayModeListView` as a fallback
  - Verification: click to enable HiDPI → the mode list refreshes automatically and new HiDPI scaled resolutions appear (such as 1920x1080 HiDPI)

- [x] Improve the HiDPI grouping of DisplayMode
  - Implementation hints:
    1. Grouping logic in `DisplayModeListView.swift`: add a "HiDPI scaled modes" group dedicated to modes where `isHiDPI && !isNative`
    2. For a 2K display (such as the user's HKC 2560x1440), the HiDPI scaled modes should include: 1280x720 HiDPI (native 2x) and lower-resolution HiDPI modes
    3. Show "logical resolution @ actual pixel density" on each mode row to help users understand what HiDPI means
  - Verification: the mode list is clearly grouped into "Default and native modes", "HiDPI scaled modes", and "Other modes"

**Phase acceptance**: builds + all four verification scenarios above are satisfied
