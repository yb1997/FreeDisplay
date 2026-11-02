# Phase 22: Auto-brightness rewrite — follow the built-in display

> Status: Complete | Estimate: high complexity

## Goal

Rewrite the auto-brightness feature: drop the Intel-only AppleLMUController approach and instead **watch the built-in display's brightness changes and sync them proportionally to external displays**. This is the approach BetterDisplay uses, and it's stable and reliable on Apple Silicon.

## Technical approach

macOS already adjusts the built-in display's brightness automatically (based on ambient light). FreeDisplay only needs to:
1. Poll the built-in display's current brightness every 2 seconds (`IODisplayGetFloatParameter` or the CoreDisplay private API)
2. If the brightness changes by more than a threshold (2%), sync it to the external displays using the user's mapping curve
3. Set the external displays' brightness through DDC VCP 0x10, or the gamma table software fallback

**Key APIs**:
- Reading built-in display brightness: `CoreDisplay_Display_GetUserBrightness(displayID)` — reliable on Apple Silicon
- Alternative: `IODisplayGetFloatParameter(service, kNilOptions, kIODisplayBrightnessKey, &brightness)`
- Setting external display brightness: reuse the existing `BrightnessService.setBrightness()`

## Tasks

### Task 1: Rewrite AutoBrightnessService — follow mode
- [x] Remove the `AppleLMUController` sensor polling logic (delete all of `findSensorPort`, `readAmbientLux`, etc.)
- [x] Add `readBuiltinBrightness() -> Double?`: reads the built-in display's current brightness (0.0-1.0)
  - Preferred: `@_silgen_name("CoreDisplay_Display_GetUserBrightness") func CoreDisplay_Display_GetUserBrightness(_ display: CGDirectDisplayID) -> Double`
  - Alternative: `IODisplayGetFloatParameter` walking IODisplayConnect
- [x] Add `@Published var builtinBrightness: Double = 0` to replace `lastLux`
- [x] Change the polling logic to: read the built-in display's brightness → if it changed by > 2% → compute the external display's target brightness with the mapping curve → call BrightnessService
- [x] Mapping curve: `externalTarget = builtinBrightness * sensitivityMultiplier` (sensitivity range 0.5-1.5, default 1.0)
- [x] Keep the 30-second manual adjustment cooldown
- [x] Keep the UserDefaults keys `fd.AutoBrightnessEnabled` and `fd.AutoBrightnessSensitivity`

**Implementation hint**: `CoreDisplay_Display_GetUserBrightness` is a private API but exists reliably on macOS 14+, and open-source projects such as MonitorControl/Lunar use it. Declaring it with `@_silgen_name` is enough. If `CoreDisplay_Display_GetUserBrightness` returns 0 (on some OS versions), fall back to IODisplayGetFloatParameter.

### Task 2: Rewrite AutoBrightnessView — adapt to the new approach
- [x] Remove the `lastLux` display (there's no lux value anymore)
- [x] Show "Built-in display brightness: XX%" instead (`builtinBrightness` shown live)
- [x] Change the sensor-unavailable hint to "No built-in display detected" (shown only when there's no built-in display)
- [x] Keep the sensitivity slider, and change its label to "Sync ratio"
- [x] Add explanatory text: "Automatically adjust external displays to follow the built-in display's brightness"

**Implementation hint**: Change the `sensorUnavailable` logic to check `builtinBrightness > 0 || hasBuiltinDisplay`, and stop checking lux.

### Task 3: Verify reading the built-in display brightness
- [x] Write a temporary test: at AppDelegate launch, print `CoreDisplay_Display_GetUserBrightness(builtinDisplayID)` to `~/Desktop/brightness_test.log`
- [x] Adjust the brightness slider manually and confirm the reading changes live (range 0.0-1.0)
- [x] If CoreDisplay returns 0 or an abnormal value → switch to the IODisplayGetFloatParameter path
- [x] Delete the temporary test code once the test passes

**Implementation hint**: Filter for the built-in display ID with `CGDisplayIsBuiltin(displayID)`. For debugging, a file log is more reliable than print (a menu bar app has no stdout).

### Task 4: Build verification + integration testing
- [x] Build passes
- [x] Real-world test: turn on auto brightness → adjust the MacBook brightness → check whether the external display follows
- [x] Edge cases: unplug the external display → no crash; with no built-in display → show the hint
- [x] Update the AutoBrightnessService description in `docs/CODEMAP.md`

## Acceptance criteria

```bash
# Build passes
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# Manual testing
# 1. Turn on auto brightness → adjust the MacBook brightness → the external display's brightness follows
# 2. Adjust the "Sync ratio" slider → the external display responds
# 3. Adjust the external display's brightness manually → auto brightness doesn't override it for 30 seconds
# 4. Close the lid/unplug the display → no crash
```
