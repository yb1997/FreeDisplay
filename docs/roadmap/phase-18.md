# Phase 18: Stability hardening

> Status: Complete | Estimate: medium complexity

## Goal

Extend the timeout protection pattern for blocking CG calls across the whole project, make sure HiDPI state is restored automatically after sleep/wake, and reapply the arrangement automatically after display configuration changes.

## Tasks

### Task 1: Unified timeout protection for blocking CG calls
- [x] Extract VirtualDisplayService's `runWithTimeout` into a shared utility function (put it in `Utilities/` or `Services/CGHelpers.swift`)
- [x] MirrorService: wrap the `CGCompleteDisplayConfiguration` calls in `enableMirror`/`disableMirror` with `runWithTimeout`
- [x] ArrangementService: wrap the `CGCompleteDisplayConfiguration` call in `setPosition` with `runWithTimeout`
- [x] ResolutionService: add 10-second timeout protection to `applyModeSync` (it currently waits forever on `CGCompleteDisplayConfiguration`)

**Implementation hint**: `runWithTimeout` has already been proven in VirtualDisplayService; reuse the same pattern directly. Watch the `@Sendable` constraint.

### Task 2: Automatic re-arrangement after display configuration changes
- [x] Register `CGDisplayRegisterReconfigurationCallback` in AppDelegate or DisplayManager
- [x] In the callback, detect when the configuration change completes (after a callback whose `flags` contain `beginConfigurationFlag`, wait for one that doesn't)
- [x] After a configuration change completes, call `displayManager.arrangeExternalAboveBuiltin()` after a 500 ms delay
- [x] Avoid repeated triggers: use a debounce mechanism so multiple callbacks within 500 ms run only the last one

**Implementation hint**: Use `Unmanaged.passRetained(self)` for the context parameter of `CGDisplayRegisterReconfigurationCallback` to prevent dangling pointers (CLAUDE.md already has this rule). The callback runs on a system thread, so switch back to the main thread with `DispatchQueue.main.async`.

### Task 3: Automatically restore HiDPI after sleep/wake
- [x] In AppDelegate's `didWakeNotification` handler, check whether `VirtualDisplayService.hiDPIActiveDisplayIDs` has an active session
- [x] If it does, check whether the virtual display is still online (`CGDisplayIsOnline`); if it's lost, recreate it + mirror + apply the resolution
- [x] Restore sequence: create → apply settings → sleep 500 ms → mirror → sleep 500 ms → setDisplayMode → arrangeExternalAboveBuiltin
- [x] Persist HiDPI state to UserDefaults (`fd.hiDPI.activePhysicalIDs`) so it can also be restored after the app restarts

**Implementation hint**: WindowServer needs time to settle after wake, so add a 2-second initial delay to the whole restore sequence. Refer to the existing `enableHiDPIVirtual` flow in VirtualDisplayService.

### Task 4: Error recovery and user feedback
- [x] Show a menu bar status hint when a CG call times out (not a popup; use the `statusMessage` pattern)
- [x] Prompt the user to turn HiDPI back on manually when HiDPI restore fails
- [x] Automatically disable HiDPI and notify the user after 3 consecutive failures

**Implementation hint**: Reuse the existing `statusMessage` pattern from HiDPIVirtualRowView.

## Acceptance criteria

```bash
# Build passes
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# Manual testing
# 1. Turn on HiDPI → close the lid to sleep → wake → HiDPI restores automatically + arrangement is correct
# 2. Turn on HiDPI → unplug the external display → plug it back in → no crash
# 3. Switch resolution → arrangement stays directly above
```
