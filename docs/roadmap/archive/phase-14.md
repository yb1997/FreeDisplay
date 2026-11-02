# Phase 14: Performance optimization (eliminating stutter)

> Goal: move every blocking IOKit/CG call off the main thread, and reduce unnecessary SwiftUI redraws

## Task list

- [x] Move BrightnessService's IOKit calls to a background thread
  - Implementation hints:
    1. `BrightnessService.swift`: run `getInternalBrightness()` and `setInternalBrightness()` on a dedicated `DispatchQueue(label: "brightness")`
    2. Make the public methods `setBrightness()` and `refreshBrightness()` `async`, wrapping the work in `withCheckedContinuation`
    3. Call them from the call sites (`BrightnessSliderView`) with `Task { await ... }`, and have the slider's `onEditingChanged` trigger the async set
    4. Add a debounce: don't send while the slider is being dragged; send only the final value on release (onEditingChanged false)
  - Verification: drag the brightness slider → the UI doesn't stutter, and the brightness changes smoothly after release

- [x] Move the IOKit queries in DisplayInfo.init to the background
  - Implementation hints:
    1. `DisplayInfo.swift`: the initializer only sets displayID and the basic CG properties (name temporarily uses "Display \(id)")
    2. Add a `func loadDetails() async` method that runs `lookupDisplayName()` and `DisplayMode.availableModes()` in the background
    3. `DisplayManager.refreshDisplays()` first creates the DisplayInfo objects (fast, non-blocking), then loads the details asynchronously with `Task { await display.loadDetails() }`
    4. When loading finishes, update the `@Published` properties on `@MainActor` to trigger a UI refresh
  - Verification: plug in a display → the new display appears in the list immediately (the name briefly shows as the ID), and the name and mode list update once the details load asynchronously

- [x] Make ColorProfileService.enumerateProfiles async
  - Implementation hints:
    1. `ColorProfileService.swift`: make `enumerateProfiles()` an `async` method that scans the file system in the background with `Task.detached`
    2. `ColorProfileView.swift`: `loadProfiles()` uses `Task { profiles = await svc.enumerateProfiles() }`
    3. Show a ProgressView animation while loading; when profiles is empty, show the loading animation instead of "No profiles"
  - Verification: open the color management panel → the loading animation shows → the profile list fills in asynchronously

- [x] Split DisplayInfo's @Published properties to reduce cascading redraws
  - Implementation hints:
    1. Split `DisplayInfo`: put the basic info (immutable properties such as name, displayID, isBuiltin) in a struct
    2. Keep the dynamic properties (brightness, currentDisplayMode, etc.) @Published, but group them into dedicated ObservableObject child objects
    3. Or a simpler approach: in `DisplayDetailView`, limit each section's redraw scope with `EquatableView` or `.id()`
    4. Simplest approach (recommended): extract each section (brightness, resolution, color, etc.) into its own View struct, each `@ObservedObject` observing only the properties it needs. Thanks to SwiftUI's view identity mechanism, collapsed sections don't observe
  - Verification: while dragging the brightness slider, confirm with the SwiftUI profiler in Instruments that other sections don't redraw; or add `let _ = print("xxx re-render")` to the body of the other sections to confirm they aren't triggered

- [x] Remove synchronous CG calls from View bodies
  - Implementation hints:
    1. Line 99 of `DisplayDetailView.swift`, `Text(ColorProfileService.shared.currentColorSpaceName(...))` → fetch it asynchronously in `onAppear` instead and store it in `@State var colorSpaceName: String`
    2. Line 125, `Text(ColorProfileService.shared.colorModeDescription(...))` → same as above
    3. If other section headers have similar synchronous service calls, change them all to the `@State` + `onAppear`/`task {}` pattern
  - Verification: builds + opening DisplayDetailView doesn't stutter

- [x] Optimize DDCService batch read performance
  - Implementation hints:
    1. In `readBatchVCPCodes()` of `DDCService.swift`, change `Thread.sleep(forTimeInterval: 0.05)` → `try await Task.sleep(nanoseconds: 30_000_000)` (30 ms, previously 50 ms)
    2. Make the method an `async` version and use a `TaskGroup` to read non-adjacent VCP codes in parallel (the same device on an I2C bus can't truly run in parallel, but smaller intervals can be used)
    3. Or a caching strategy: do one full read first, then afterwards read only the VCP code the user is working with, using cached values for the rest
  - Verification: open the integrated control panel → the time to read 11 VCP codes drops from ~550 ms to ~330 ms

**Phase acceptance**: builds + opening/operating every panel has no noticeable stutter (subjectively smooth)
