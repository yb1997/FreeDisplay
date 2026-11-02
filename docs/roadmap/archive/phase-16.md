# Phase 16: Comprehensive bug fixes

> Goal: fix the 37 issues found in the audit, in three batches by priority

## Batch A: P0 — Crashes/data loss (5)

- [x] A1: Fix the race condition when AutoBrightnessService iterates displays
  - **File**: the applyBrightness method of `AutoBrightnessService.swift`
  - **Problem**: accessing `DisplayManagerAccessor.shared.displays` and modifying `display.brightness` has no synchronization, so hot-plugging can crash
  - **Fix**: take an array snapshot with `let snapshot = displays` before iterating, or add `@MainActor` to guarantee main-thread access
  - **Verification**: hot-plugging a display with auto brightness on doesn't crash

- [x] A2: Fix the memory leak in BrightnessService refreshBrightness
  - **File**: the refreshBrightness method of `BrightnessService.swift`
  - **Problem**: the completion handler of DDCService.shared.readAsync() implicitly captures self, so the callback dangles after display is released
  - **Fix**: capture `[weak self]` in the completion, with `guard let self else { return }` inside the callback
  - **Verification**: after refreshing brightness repeatedly, Instruments shows no memory leak

- [x] A3: Fix the boundary condition in BrightnessSliderView onChange
  - **File**: onChange(of: display.brightness) in `BrightnessSliderView.swift`
  - **Problem**: `abs(newValue - localBrightness) > 1` uses `>`, so a change of exactly 1% doesn't sync
  - **Fix**: change it to `abs(newValue - localBrightness) >= 1`
  - **Verification**: changing the brightness externally by 1% → the UI updates to match

- [x] A4: Fix the sparse cache problem in DDCService readBatchVCPCodes
  - **File**: the readBatchVCPCodes method of `DDCService.swift`
  - **Problem**: building the dictionary from the cache with compactMap skips missing codes, so the result has fewer entries than requested with no indication
  - **Fix**: do real reads for codes that miss the cache, and mark explicitly in the final result which reads failed (return `[UInt8: UInt16?]`)
  - **Verification**: batch-read 11 VCP codes → all are returned (succeeded or explicitly failed)

- [x] A5: Fix DisplayModeListView resolution switching having no error handling
  - **File**: the switchTo method of `DisplayModeListView.swift`
  - **Problem**: when `ResolutionService.shared.setDisplayMode()` fails, there's no retry and no user feedback
  - **Fix**: show an error toast on failure (with `@State var errorMessage`), and add one automatic retry
  - **Verification**: simulate a failed switch → the user sees an error message

## Batch B: P1 — Malfunctions (11)

- [x] B1: Fix the hard-coded initial brightness in DisplayInfo
  - **File**: init of `DisplayInfo.swift`
  - **Problem**: the built-in display's brightness is initialized to 50.0 without reading the actual value
  - **Fix**: right after init completes, call `BrightnessService.shared.refreshBrightness(for: self)` to read the real value
  - **Verification**: open the app → the brightness slider shows the real system brightness

- [x] B2: Fix the single-display state key in GammaService
  - **File**: saveState/loadSavedState in `GammaService.swift`
  - **Problem**: the UserDefaults key is fixed as `"GammaService.savedAdjustment"`, so with multiple displays only the last one is saved
  - **Fix**: change the key to `"GammaService.savedAdjustment.\(displayID)"`
  - **Verification**: adjust the gamma on two displays separately → restart the app → each restores its correct value

- [x] B3: Fix the async defer running early in MirrorView
  - **File**: the toggleMirror method of `MirrorView.swift`
  - **Problem**: `defer { isSwitching = false }` runs before the await in an async function, so the loading state disappears instantly
  - **Fix**: remove the defer, and set `isSwitching = false` separately after the await completes and in the catch block
  - **Verification**: click the mirroring button → the loading animation lasts until the operation completes

- [x] B4: Fix the race condition in ColorProfileView loadProfiles
  - **File**: loadProfiles in `ColorProfileView.swift`
  - **Problem**: after the View disappears, the async task still updates @State, triggering a SwiftUI warning
  - **Fix**: use `.task { }` instead of a manual Task (SwiftUI cancels it automatically), or add `@State var loadTask: Task<Void, Never>?` and cancel it in onDisappear
  - **Verification**: expand/collapse the color panel quickly → no console warnings

- [x] B5: Fix the non-MainActor state update in IntegratedControlView
  - **File**: readFromDevice in `IntegratedControlView.swift`
  - **Problem**: a non-@MainActor method updates @State variables directly
  - **Fix**: mark the method `@MainActor`, or use `await MainActor.run { isReading = false }`
  - **Verification**: builds with no concurrency warnings

- [x] B6: Fix the concurrency issue in ColorProfileView applyProfile
  - **File**: applyProfile in `ColorProfileView.swift`
  - **Problem**: the function isn't marked @MainActor but updates UI state inside
  - **Fix**: mark it `@MainActor`
  - **Verification**: applying an ICC profile → no concurrency warnings

- [x] B7: Verify the HiDPIService plist path construction (confirmed correct, no change needed)
  - **File**: overridePlistURL in `HiDPIService.swift`
  - **Problem**: the audit pointed out that the vendor/product path might be wrong
  - **Fix**: check whether the generated plist path matches the path macOS expects (`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-YYYY`), and correct any mismatch
  - **Verification**: write the plist → confirm the path is correct with `ls` → HiDPI appears after the mode list is re-enumerated

- [x] B8: Fix the DisplayDetailView task not being cancelled
  - **File**: .task(id:) in `DisplayDetailView.swift`
  - **Problem**: after a display disconnects and reconnects, the old task may update stale data
  - **Fix**: check the cancellation state with `Task.checkCancellation()` after the await
  - **Verification**: hot-plug a display → the detail panel data is correct

- [x] B9: Fix RotationService returning an inaccurate value
  - **File**: setRotation in `RotationService.swift`
  - **Problem**: it returns the result of `IOServiceRequestProbe`, but that only means the probe request succeeded, not that the rotation took effect
  - **Fix**: after the probe, sleep 100 ms, then verify the actual angle with `CGDisplayRotation(displayID)`
  - **Verification**: rotate a display → the return value accurately reflects whether it took effect

- [x] B10: Clean up the DisplayInfo.lookupDisplayName dead code
  - **File**: lookupDisplayName in `DisplayInfo.swift`
  - **Problem**: this method is never called (it was replaced by NSScreen.localizedName)
  - **Fix**: delete the whole method
  - **Verification**: builds

- [x] B11: Fix the ResolutionService .permanently vs .forSession inconsistency
  - **File**: `ResolutionService.swift` vs `ArrangementService.swift`
  - **Problem**: resolution uses .permanently while arrangement uses .forSession, so the behavior is inconsistent
  - **Fix**: change both to `.forSession` (it's safer to let macOS restore the system settings after a restart), or use `.permanently` for both and document it
  - **Verification**: switch resolution/arrangement → after a restart the behavior matches expectations

## Batch C: P2 — Minor issues/code quality (21)

- [x] C1: AutoBrightnessService readAmbientLux may block the main thread
  - **Fix**: make sure it's called from a background thread, or dispatch to a background queue inside the method

- [x] C2: The AutoBrightnessService lux scaling constant is undocumented
  - **Fix**: add a comment explaining where `rawAvg / 1_000_000.0 * 1_000.0` comes from

- [x] C3: BrightnessSliderView DispatchAfter isn't cancellable
  - **Fix**: replace it with a `DispatchWorkItem`, or use SwiftUI `.task` + `Task.sleep`

- [x] C4: ColorProfileService assumes the ICC header is ASCII
  - **Fix**: add an encoding check, with a fallback for non-ASCII

- [x] C5: DDCService buffer count capture is fragile
  - **Fix**: inline the count or extract a helper method

- [x] C6: Redundant filter logic in DisplayModeListView
  - **Fix**: simplify `.filter { $0.isNative || (!$0.isHiDPI && $0.isNative) || ($0.isNative) }` to `.filter { $0.isNative }`

- [x] C7: Boundary condition for quantization in ImageAdjustmentView
  - **Fix**: change `quantLevels >= 256` to `quantLevels >= 255` or `== 256`

- [x] C8: ImageAdjustmentView resetAll lacks a MainActor guarantee
  - **Fix**: confirm GammaService.restoreColorSync() is called on the MainActor

- [x] C9: The MenuBarView update check may block the UI
  - **Fix**: add a timeout and move it to the background

- [x] C10: HiDPIService refreshModes isn't awaited
  - **Fix**: store the Task reference and cancel it when appropriate

- [x] C11: Inconsistent lock release and callback order in DDCService
  - **Fix**: standardize on the "unlock first, then call back" pattern

- [x] C12: VirtualDisplayService addAndCreate doesn't roll back when creation fails
  - **Fix**: remove it from configs when `create()` fails

- [x] C13: ArrangementService .forSession may not be what the user expects
  - **Fix**: handle together with B11

- [x] C14: UpdateService JSON parsing fails silently
  - **Fix**: add a `print("[UpdateService] JSON parse error:")` log

- [x] C15: Overuse of withCheckedContinuation in BrightnessService
  - **Fix**: return directly after dispatching async, or simplify to a synchronous call

- [x] C16: DisplayDetailView @EnvironmentObject MainActor isn't annotated explicitly
  - **Fix**: add a comment explaining it

- [x] C17: Concurrency safety of the BrightnessSliderView @ObservedObject
  - **Fix**: make sure every DisplayInfo update happens on the main thread

- [x] C18: Theoretical memory pointer safety issue in DDCService
  - **Fix**: confirm the withUnsafeMutableBytes usage is correct (it is; marked as reviewed)

- [x] C19: IOObjectRelease iterator cleanup in BrightnessService
  - **Fix**: confirm the iterator is fully exhausted before it's released (it is; marked as reviewed)

- [x] C20: The ResolutionSliderView reference in DisplayDetailView
  - **Fix**: confirm the component exists, otherwise remove the reference

- [x] C21: Global code cleanup — remove unused imports and commented-out code
  - **Fix**: scan and clean up globally

## Acceptance criteria

```bash
# 1. Builds with no warnings
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | grep -E "warning:|error:" | head -20

# 2. Manual test checklist
# - Open the app → brightness shows the real value (not 50%)
# - Hot-plug a display → no crash
# - Adjust the gamma → close the panel → the screen returns to normal
# - Mirroring → the loading animation shows the whole time
# - Switch the color profile → no console warnings
# - HiDPI toggle → the plist is written to the correct path
```
