# Lessons Learned — CoreGraphics

> Updated: 2026-03-05

## CoreGraphics / Displays

- In a Swift 6 class init, if an `@Published` property isn't initialized yet, you can't use `self.anyProperty` before initialization finishes (even if that property has been assigned) → fix: save the value in a local variable and reference that
- `CGDisplayRegisterReconfigurationCallback` requires the callback to be a C function pointer (a global func), not a closure → pass `Unmanaged.passUnretained(self).toOpaque()` through `userInfo`
- In Swift 6, `deinit` is nonisolated and can't access `@MainActor`-isolated properties → fix: mark the properties deinit needs as `nonisolated(unsafe)`
- If the build reports "symbol not found" after adding a Swift source file, rerun `xcodegen generate` to regenerate the xcodeproj (even when project.yml uses a glob, an old xcodeproj may not include the new file)
- The macOS 26.2 SDK replaces C functions such as `CGDisplayModeGetWidth/Height/PixelWidth/PixelHeight/RefreshRate/IODisplayModeID` with Swift properties (`mode.width`, `mode.pixelWidth`, `mode.ioDisplayModeID`, etc.) and methods (`mode.isUsableForDesktopGUI()`) → with the new SDK, use the property syntax directly and avoid the deprecated functions
- `kCGDisplayShowDuplicateLowResolutionModes: true` is the correct key name; passing it in the options dictionary of `CGDisplayCopyAllDisplayModes` shows the HiDPI scaled modes
- In the macOS 26 SDK, `CGDisplayCopyColorSpace` returns a non-Optional `CGColorSpace` (older SDKs returned an Optional) → change the guard let to a direct call, and use `colorSpace.name` for the name (`CGColorSpaceCopyName` has been replaced by a property)
- `CGDisplayMode.pixelEncoding` is a `CFString?` (not a `String`) and must be bridged manually: `if let cfEnc = mode.pixelEncoding { encoding = cfEnc as String }`
- ColorSync global constants (`kColorSyncDisplayDeviceClass`, `kColorSyncDeviceDefaultProfileID`) are of type `Unmanaged<CFString>?` in Swift 6, and accessing the global vars produces concurrency-safety warnings → use `@preconcurrency import ColorSync` to suppress the concurrency errors; borrow the reference with `.takeUnretainedValue()` when accessing them (not `takeRetainedValue`, to avoid a double release)
- `kColorSyncProfileUseSystemSequence` doesn't exist in the public ColorSync headers → resetting to the system default profile can't be done through the public interface, so resetProfile was skipped
- After adding a Swift source file you must rerun `xcodegen generate` to regenerate the xcodeproj; otherwise the compiler doesn't know about the new file ("cannot find in scope" error)

## HiDPI / Resolution

- After `HiDPIService` writes the display override plist, macOS doesn't load the new modes right away → you need to trigger display re-enumeration (`CGDisplayForceToMirror` or `IOServiceRequestProbe`)
- `isUsableForDesktopGUI()` filters out some resolution modes, so some resolutions are "invisible" → this filter may need to be bypassed

### L-006: On macOS 14+, plist injection can't enable HiDPI dynamically
- **Symptom**: after writing the display override plist + IOServiceRequestProbe, the 2K external display doesn't show HiDPI modes
- **Cause**: macOS Ventura/Sonoma doesn't dynamically re-enumerate plist-injected modes for a display that's already connected. The plist approach only works when the display is first connected
- **Solution**: use the CGVirtualDisplay private API to create a 3840x2160 virtual display (hiDPI=1), then mirror the physical display to the virtual display; macOS automatically provides HiDPI modes such as 1920x1080@2x
- **Lesson**: the core of BetterDisplay's HiDPI approach is "virtual display + mirroring", not plist injection
- **Date**: 2026-03-03

### L-007: NSWindow.isReleasedWhenClosed defaults to true
- **Symptom**: the app crashes/hangs when the notch overlay is closed
- **Cause**: NSWindow defaults to `isReleasedWhenClosed = true`, so after close() the window is released by ARC immediately and the reference in the dictionary becomes a dangling pointer
- **Solution**: set `isReleasedWhenClosed = false` right after creating the NSWindow
- **Lesson**: the project's other windows (PiPWindow, StreamWindow, VideoFilterWindow) all set this property correctly; only NotchOverlayManager missed it
- **Date**: 2026-03-03

## CGVirtualDisplay / Virtual displays

- `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`, `CGVirtualDisplaySettings`, and `CGVirtualDisplayMode` are private CoreGraphics SPI. Their symbols are exported in the TBD file (`grep CGVirtualDisplay CoreGraphics.tbd`), but they aren't declared in the public C/ObjC headers or the Swift interface files of the macOS 26 SDK → referencing them directly from Swift gives a "cannot find type in scope" error
- BetterDisplay/BetterDummy use these classes by declaring their own private interface header (bridging header) → this counts as private API use, and the project must explicitly decide whether to accept that risk
- If asked to resolve this before continuing, read BLOCKING.md B-002 first

### L-020: CGVirtualDisplay vendorID must be non-zero
- **Symptom**: `CGVirtualDisplay(descriptor:)` always returns nil, with no error
- **Cause**: WindowServer rejects `vendorID = 0`; the node-mac-virtual-display project uses `0xEEEE`
- **Solution**: set `vendorID = 0xEEEE`, `productID = 0x0001`, `serialNum = 0x0001`
- **Lesson**: the implicit constraints of private APIs are undocumented; you must refer to known working open-source implementations
- **Date**: 2026-03-04

### L-021: CGVirtualDisplay(descriptor:) must run on the main thread
- **Symptom**: calling it from a background DispatchQueue returns nil; calling it on the main thread succeeds
- **Cause**: WindowServer IPC requires CGVirtualDisplay initialization on the main thread
- **Solution**: build the descriptor + init on @MainActor; run `apply(settings)` and `enableMirror` in the background through `runWithTimeout`
- **Lesson**: different methods of the same API can have different threading requirements
- **Date**: 2026-03-04

### L-022: Bridging header property names must exactly match the runtime API
- **Symptom**: `-[CGVirtualDisplayDescriptor setMaxPixelSize:]: unrecognized selector` causes a crash
- **Cause**: the bridging header declared `maxPixelSize` (CGSize), but the real property names are `maxPixelsWide`/`maxPixelsHigh` (uint32_t)
- **Solution**: use Chromium's `virtual_display_mac_util.mm` as the authoritative reference and verify every property name
- **Lesson**: you can't guess property names in a private API bridging header; refer to reverse engineering or a known working implementation
- **Date**: 2026-03-04

### L-023: HiDPI virtual display configurations must not autoCreate
- **Symptom**: every app restart piles up stale virtual displays (displayID=7,8,9,10...), until creation eventually fails
- **Cause**: the HiDPI config was stored in the configs array with `autoCreate: true`, but autoCreate only creates the virtual display without mirroring, so useless virtual displays pile up
- **Solution**: HiDPI configurations are runtime-only (`autoCreate: false`, not stored in configs), and leftovers are cleaned up at launch
- **Lesson**: configurations that depend on runtime state (such as a mirroring relationship) shouldn't be rebuilt automatically — after rebuilding they lack key context
- **Date**: 2026-03-04

### L-024: CGDisplayMirrorsDisplay() detection is unreliable
- **Symptom**: switching resolution fails in HiDPI mode; `CGDisplayMirrorsDisplay(physicalID)` returns `kCGNullDirectDisplay`
- **Cause**: macOS's mirroring detection API doesn't always recognize mirroring relationships set up with `CGConfigureDisplayMirrorOfDisplay`
- **Solution**: add `VirtualDisplayService.virtualDisplayID(for:)` as a fallback in `resolvedTargetDisplayID()`
- **Lesson**: system API behavior can differ from the documentation; you need a fallback
- **Date**: 2026-03-04

### L-025: Choosing a HiDPI approach — mirroring is a dead end, the plist override is the right way
- **Symptom**: using CGConfigureDisplayMirrorOfDisplay to create a virtual display → mirror it to the external display to get HiDPI modes triggered the system "Screen Mirroring" UI + mouse stutter across screens + pure mirroring mode
- **Cause**: Apple Silicon's WindowServer manages hardware mirroring strictly, and CGConfigureDisplayMirrorOfDisplay triggers the full mirroring reconfiguration flow
- **Solution**: switch to a plist override (write to /Library/Displays/Contents/Resources/Overrides/), which is BetterDisplay's approach. It needs administrator privileges (NSAppleScript "with administrator privileges") and takes effect after the display is reconnected
- **Lesson**: don't use CGConfigureDisplayMirrorOfDisplay for HiDPI; it's a dead end on Apple Silicon

### L-026: Loading private framework symbols — dlsym, not @_silgen_name
- **Symptom**: declaring a private function with @_silgen_name("CoreDisplay_Display_GetUserBrightness") builds, but linking fails (undefined symbol)
- **Cause**: @_silgen_name needs the symbol to be visible at link time, and CoreDisplay is a private framework that isn't in the default link path
- **Solution**: load at runtime with dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) + dlsym
- **Lesson**: always use dlopen+dlsym for private framework symbols, never @_silgen_name

### L-027: display.pixelWidth is the current resolution, not the native resolution
- **Symptom**: the scale-resolutions array in the HiDPI plist override is empty
- **Cause**: display.pixelWidth/pixelHeight (from CGDisplayPixelsWide/High) were passed in as the native resolution, but the display may currently be at a non-native resolution
- **Solution**: use display.availableModes.max(by: width*height) to get the largest available mode as the native resolution
- **Lesson**: CGDisplayPixelsWide/High return the pixel size of the current mode, not the panel's physical resolution

### L-030: CGDisplayIOServicePort is 0 for every display on Apple Silicon
- **Symptom**: virtual display auto-create was skipped when a real monitor ran at the same size as a saved virtual config
- **Cause**: the dedupe check treated "service port == 0" as "virtual display"; on Apple Silicon physical displays also return 0 (and there are no IODisplayConnect services)
- **Solution**: identify FreeDisplay's virtual displays by `CGDisplayVendorNumber == VirtualDisplayService.virtualVendorID`
- **Lesson**: never use the service port to tell physical from virtual displays, or to find a display's IOKit service, on Apple Silicon
- **Date**: 2026-11-02

### L-031: setModeFlag also fires for macOS's own sleep/wake mode resets
- **Symptom**: a resolution saved by FreeDisplay overrode later System Settings changes on every wake; naively following every setModeFlag would instead record the wake reset and break wake re-apply
- **Cause**: the reconfiguration callback can't tell user changes from the system's resets around sleep
- **Solution**: `ResolutionService.noteModeChanged` follows outside changes only for displays FreeDisplay already manages, and is suppressed from willSleep until 3 s after the wake re-apply
- **Lesson**: any "follow external changes" logic on display reconfiguration needs a sleep/wake suppression window
- **Date**: 2026-11-02

### L-036: Reset gamma by re-assigning the color profile, not with an identity table
- **Symptom**: closing Image Adjustments or "Reset All" dropped software dimming and removed the user's custom ICC profile; positive contrast/gain did nothing
- **Cause**: reset wrote identity and removed the custom profile; the formula path clamped `hi` to 1, so values that should stretch were clamped away
- **Solution**: GammaService builds one 256-entry table (adjustment × software brightness factor). With nothing active it calls `ColorSyncDeviceSetCustomProfiles` with the display's current profile (NSNull when none), which reloads the profile's curve including any calibration (probe: a 0.8-dimmed table went back to 1.0)
- **Lesson**: an identity table is not the baseline when a profile carries a calibration curve; never write gamma from `onDisappear`
- **Date**: 2026-11-02

### L-037: Move displays in one configuration transaction, and don't auto-arrange on movedFlag
- **Symptom**: "Set as Main Display" mirrored a two-display layout; auto-arrange stacked every external display on the same spot
- **Solution**: shift every display by `-target.origin` in one `CGBeginDisplayConfiguration` transaction (`ArrangementService.setOrigins`); lay externals side by side; skip when already in place; react to `.movedFlag` with a bounds refresh only, so user drags in System Settings aren't snapped back
- **Date**: 2026-11-02
