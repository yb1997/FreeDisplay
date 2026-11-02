# Lessons Learned — Cross-Service Coordination / Concurrency / Resource Management

> Updated: 2026-03-05

## Feature interaction / Cross-Service coordination (Round 3-4 optimization)

### L-008: Two Services writing the same CoreGraphics resource overwrite each other
- **Symptom**: after setting a gamma adjustment, dragging the brightness slider makes the gamma effect disappear (or vice versa)
- **Cause**: GammaService and BrightnessService both call CGSetDisplayTransfer*, and whichever calls last completely overwrites the other
- **Solution**: designate GammaService as the single writer; BrightnessService stores the brightness factor in softwareBrightnessFactors, and GammaService reads it in applyFormula and multiplies it into rHi/gHi/bHi
- **Lesson**: when two Services share an underlying resource, you must designate a single owner, and the others influence it through its interface instead of writing directly
- **Date**: 2026-03-04

### L-009: macOS sleep/wake resets every CGSetDisplayTransfer* effect
- **Symptom**: gamma adjustments and software brightness are all lost after the Mac sleeps
- **Cause**: macOS resets the display transfer function to the system default during sleep, so CGSetDisplayTransfer* effects don't persist
- **Solution**: register for NSWorkspace.didWakeNotification, and after wake, wait 500 ms and reapply to every display
- **Lesson**: every feature that writes display hardware state must handle the reset after sleep/wake, and testing must cover this scenario
- **Date**: 2026-03-04

### L-010: CGDisplayRegisterReconfigurationCallback must use passRetained
- **Symptom**: theoretical crash risk: the C callback accesses a dangling pointer
- **Cause**: passUnretained doesn't increase the reference count, so after self is released the callback accesses a dangling pointer
- **Solution**: passRetained + a paired release (in stopMonitoring/deinit)
- **Lesson**: always use passRetained for a self pointer passed to a C callback; this has come up twice in the project (DisplayManager + ConfigProtectionService)
- **Date**: 2026-03-04

### L-011: AutoBrightness and manual adjustment must have a cooldown mechanism
- **Symptom**: 2 seconds after brightness is adjusted manually, AutoBrightness overrides it
- **Cause**: applyBrightness only checked the difference and had no "user adjusted it manually recently" protection
- **Solution**: add an isAutoAdjust parameter to setBrightness; manual calls record lastManualAdjustDate, and AutoBrightness checks a 30 s cooldown
- **Lesson**: automatic adjustment features must pause after manual intervention
- **Date**: 2026-03-04

## Concurrency / Resource management (Round 5 optimization)

### L-012: The GammaService activeAdjustments dictionary must be locked
- **Symptom**: data race risk — BrightnessService reads hasActiveAdjustment from a background queue while GammaService writes activeAdjustments from the MainActor
- **Cause**: the dictionary has no synchronization, and concurrent multithreaded reads/writes are undefined behavior in Swift (may crash or corrupt data)
- **Solution**: add an NSLock and lock every activeAdjustments read/write (hasActiveAdjustment/apply/reapply/reset, etc.)
- **Lesson**: any mutable state accessed by more than one actor must be locked, whether or not a race is currently happening
- **Date**: 2026-03-04

### L-013: The GammaService quantization path must also apply the brightness factor
- **Symptom**: software brightness silently stops working in quantization mode (quantizationLevels < 256)
- **Cause**: applyFormula read the softwareBrightness factor but applyQuantizedTable didn't, so the two paths were inconsistent
- **Solution**: applyQuantizedTable also reads brightnessFactor and scales rHi/gHi/bHi
- **Lesson**: when a Service has more than one execution path, every path must apply the same change logic
- **Date**: 2026-03-04

### L-014: On sleep/wake, BrightnessService must reapply before GammaService
- **Symptom**: the screen briefly flashes white (full brightness) on wake before recovering
- **Cause**: when GammaService.reapply ran first, softwareBrightnessFactors hadn't been restored yet, so applyFormula read 1.0 and wrote it to the hardware
- **Solution**: on wake, call BrightnessService.reapply first, then GammaService.reapply (so the factor is ready)
- **Lesson**: reapplies with dependencies must be called in dependency order; BrightnessService supplies data to GammaService
- **Date**: 2026-03-04

### L-015: Closing an NSWindow must stop its associated SCStream
- **Symptom**: when the user clicks the red close button of the PiP/Stream window, streaming keeps running in the background and consuming resources
- **Cause**: the NSWindowController didn't implement NSWindowDelegate.windowWillClose, so the close event didn't trigger stopCapture
- **Solution**: PiPWindowController/StreamWindowController implement windowWillClose → viewModel.stopCapture(), and also set window.delegate = self
- **Lesson**: both the system-provided close control (the red button) and the in-app close button must clean up resources; handling only one isn't enough
- **Date**: 2026-03-04

### L-016: Never call removeValue while iterating a Dictionary
- **Symptom**: NotchOverlayManager.screenParametersChanged() called removeValue while iterating overlayWindows, a potential crash
- **Cause**: Swift Dictionary doesn't support modifying itself during for-in iteration; the behavior is undefined
- **Solution**: collect the keys to delete in a temporary array and delete them all after the loop
- **Lesson**: never add to or remove from a collection while iterating it with for-in (the equivalent of a ConcurrentModificationException in other languages)
- **Date**: 2026-03-04

### L-017: UserDefaults keys must have an app namespace prefix
- **Symptom**: SettingsService/AutoBrightnessService/ConfigProtectionService used bare keys (e.g. "launchAtLogin")
- **Cause**: bare keys can collide with macOS system defaults or future third-party libraries, causing unexpected values to be read or system settings to be overwritten
- **Solution**: add the `fd.` prefix everywhere (fd.launchAtLogin, fd.AutoBrightnessEnabled, etc.)
- **Lesson**: UserDefaults key naming convention: `<app_prefix>.<key>`
- **Date**: 2026-03-04

### L-018: Query direction of the mirror source/target API
- **Symptom**: refreshMirrorState queried with CGDisplayMirrorsDisplay(source), which always returned nil (the source doesn't clone anything)
- **Cause**: CGDisplayMirrorsDisplay(X) returns "the display X clones", and the SOURCE itself isn't a cloner
- **Solution**: query in reverse — walk every display and find the one where CGDisplayMirrorsDisplay(candidate) == source (that's the target)
- **Lesson**: Mirror API semantics: the SOURCE is the one being cloned, and the TARGET is the cloner; query from the TARGET's point of view ("who is cloning me")
- **Date**: 2026-03-04

### L-019: Release the old IOPMAssertion before creating a new one
- **Symptom**: ManageDisplayView leaked an IOPMAssertion every time the prevent-sleep toggle was turned on, and the old ID was overwritten so it could never be released
- **Cause**: createSleepAssertion() didn't check sleepAssertionID != 0 and overwrote it directly
- **Solution**: release the old assertion before creating a new one; onDisappear only releases when !preventSleep (so it stays in effect while the toggle is ON)
- **Lesson**: system resources (IOPMAssertion, IO iterators, etc.) must strictly pair create/release; release the old one before overwriting its ID
- **Date**: 2026-03-04

### L-028: Background-queue callbacks must be marked @Sendable (otherwise Swift 6 crashes at runtime)
- **Symptom**: FreeDisplay crashes immediately after pressing a brightness key on an external display (EXC_BREAKPOINT, `BUG IN CLIENT OF LIBDISPATCH: Block was expected to execute on queue [com.apple.main-thread]`, crashing queue `com.freedisplay.ddc`)
- **Cause**: `setBrightnessSmooth` is `@MainActor`, so the DDC completion closure written inside it inherited MainActor isolation; `DDCService.writeAsync` calls it on ddcQueue → the Swift 6 runtime isolation check traps. `SWIFT_STRICT_CONCURRENCY: minimal` doesn't affect this runtime check
- **Solution**: change the completion parameters of `writeAsync` / `readAsync` to `@Sendable` (so the closure no longer inherits the caller's isolation)
- **Lesson**: every completion parameter that's called back on your own background queue must be marked `@Sendable`; when investigating, look at the crashing queue name in `~/Library/Logs/DiagnosticReports/FreeDisplay-*.ips`
- **Date**: 2026-10-18

### L-029: Ad-hoc signing invalidates the Accessibility permission on every build
- **Symptom**: the brightness keys have no effect on the external display, even though FreeDisplay's Accessibility toggle in System Settings shows as on
- **Cause**: the designated requirement of an ad-hoc signature is the cdhash, which changes with every build; TCC records the old cdhash, so for the new build `CGEvent.tapCreate` returns nil
- **Solution**: sign with a local self-signed certificate (set `CODE_SIGN_IDENTITY` in `Config/Signing.local.xcconfig`) so the requirement becomes identifier + certificate and the permission survives rebuilds; the menu shows a hint while the tap isn't installed
- **Investigation**: get the csreq from `sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db"`, and compare `csreq -r - -t` with `codesign -dr -`; in zsh `log` is a builtin, so use `/usr/bin/log show`
- **Date**: 2026-10-18

### L-034: Loading prefs one property at a time through didSet-savers clobbers the others
- **Symptom**: Auto Brightness sensitivity reset to 1.0 at every launch (and after reordering, "enabled" reset to off)
- **Cause**: each property's `didSet` called `savePrefs()`, which writes ALL keys; assigning the first loaded value saved the still-default second value over its stored one
- **Solution**: read every value from UserDefaults into locals first, then assign
- **Lesson**: when a `savePrefs()` writes several keys, never let it run in the middle of `loadPrefs()`
- **Date**: 2026-11-02

### L-038: Self-updating without Sparkle: pin the running app's designated requirement
- **Context**: releases are signed with the self-signed "FreeDisplay Local" certificate and not notarized; the project allows no third-party dependencies
- **Solution**: UpdateInstaller checks the downloaded app with `SecStaticCodeCheckValidity` (strict, nested code, all architectures) against `SecCodeCopyDesignatedRequirement` of the RUNNING app (`identifier "com.freedisplay.app" and certificate leaf = H"…"`), and reads the version from the new app's own Info.plist. It refuses when the running copy is ad-hoc signed (its requirement is a cdhash), translocated or on a read-only volume. A file downloaded by the app itself gets no quarantine attribute, so no Gatekeeper prompt after updating
- **Testing**: `#if DEBUG` hooks only (`-FDTestInstallUpdate`, `FD_UPDATE_TEST_DMG=file://…`), run from a scratch folder outside /Applications with `MARKETING_VERSION` overridden; never publish a throwaway release (it becomes everyone's Latest)
- **Lesson**: the updater only helps from the first release that contains it; earlier users update by hand once
- **Date**: 2026-11-02

