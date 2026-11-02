# FreeDisplay Bug Report — 2026-11-02

Static review of all 41 Swift files (~7.8k lines) at commit `0dee5e2` (v1.1.0), plus read-only probes on an Apple Silicon Mac (M4 Pro, macOS 27) with one external display (vendor `1e6d`, product `5c4c`). No code was changed.

## Fix status (updated 2026-11-02)

| # | Status |
| :- | :- |
| 1 | **Fixed:** built-in brightness uses `DisplayServicesGet/SetBrightness` (owner-approved). CoreDisplay turned out to be a no-op on this Mac (Get always 1.0), so it isn't used. Probe confirmed set and restore on the real display. `HiDPIService.triggerDisplayReenumeration` is still a no-op |
| new | **Fixed:** Auto Brightness lost its saved settings at launch: `loadPrefs` assigned one property at a time and each `didSet` saved both keys, so the not-yet-loaded one was overwritten with its default (sensitivity reset to 1.0, or enabled reset to off). It also could record a reading as applied before any external display was listed |
| new | **Fixed:** Auto Brightness read the built-in brightness through CoreDisplay, which always returned 1.0, so it synced external displays to 100%. It now uses DisplayServices |
| 2 | **Fixed:** dedupe matches `VirtualDisplayService.virtualVendorID` instead of service port 0 |
| 3 | **Fixed:** `AutoBrightnessService.shared` is created in `applicationDidFinishLaunching` |
| 4 | **Fixed:** saved modes keyed by display UUID (new key `fd.ResolutionService.savedModesByUUID`, old key removed); outside mode changes update the saved mode, except from willSleep until 3 s after the wake re-apply. Wake handling moved from the menu's `.task` (which only ran once the menu was opened) into `DisplayManager` |
| 5 | **Fixed:** brightness saved by display UUID on every change; software-dimmed displays show their dimming level on the slider after re-apply (not for DDC displays) |
| 6 | **Fixed:** GammaService is the single writer and builds one table from the adjustment × software dimming. Reset/Pause/closing no longer drop dimming or remove the ICC profile; with nothing active the profile curve is restored by re-assigning the display's profile. `onDisappear` only saves state. Saved adjustments keyed by UUID (old keys migrated) |
| 7 | **Fixed:** DDC counts as unavailable only after 3 failed operations in a row; launch/wake probes retry every 2 s; DDC state and caches reset on wake |
| 8 | **Fixed:** any DDC success clears leftover software dimming; dimming is restored only once DDC counts as unavailable; factor keyed by UUID (old `fd.softBrightness_<id>` keys removed) |
| 9 | **Fixed:** `setBrightness` updates `display.brightness`; brightness keys step from the running fade's target |
| 10 | **Fixed:** table-based math: positive contrast stretches around mid-grey, positive gain brightens, everything clamped to 0–1 after inversion |
| 11 | **Fixed:** Set as Main Display shifts every display by `-target.origin` in one transaction; auto-arrange lays externals side by side, in one transaction, and skips when already in place |
| 12 | **Fixed:** the user is asked before HiDPI is enabled; declining, canceling the password prompt or turning HiDPI off opts that monitor model out (`fd.hidpi.autoEnableOptOut.<vendor>-<product>`) |
| 13 | **Fixed:** replies validated (opcode, result code, echoed VCP, checksum, max > 0) on both paths; Intel path untested |
| 14 | **Fixed:** bounds and pixel size refresh on mode/main/move changes (`.movedFlag` now handled, without auto-arrange); arrangement uses live bounds; MainDisplayView goes through DisplayManager |
| new | **Fixed (owner-confirmed):** expanding Settings, Virtual Displays or Auto Brightness near the bottom of the menu didn't scroll, so the new rows stayed hidden once the menu reached its 640 pt height cap. `MenuBarView` now scrolls the expanded section into view (`ScrollViewReader`) |
| minor | **Fixed:** Auto Brightness toggle can always be turned off; saved virtual displays have Turn On/Off; each virtual display gets its own serial (existing configs get a new identity once); "Current" preset compares HiDPI and prefers user presets; Launch at Login shows the real status and opens Login Items when approval is needed; software brightness written only on the main thread through GammaService; `ddcCacheTTL` removed; `MirrorService`, `ResolutionSliderView`, `SystemColorView` deleted |

Build passes. **Runtime test (2026-11-02, Debug build, menu never opened):**
- #3, #1 (read), #5: with Auto Brightness enabled and sensitivity 1.5, the app set the external display to 74.6% at launch (built-in 0.497 × 1.5), saved as `fd.brightness_<UUID>`. Enabled and sensitivity survived the launch.
- #4: with the external display's mode saved, switching it outside the app from 144 Hz (mode 58) to 120 Hz (61) and back updated the saved mode to 61, then 58. The old `fd.ResolutionService.savedModes` key was removed on first use.

- Rerun the same day: same results for #3, #1 (read), #5 and #4. This time the external monitor answered DDC, so Auto Brightness set it through hardware (read 85/100, wrote 74) with no software dimming. A relaunch with the same settings sent no DDC write, but that doesn't isolate the saved-value load for #5 because the launch-time DDC read also returns 74.

- Owner confirmed by hand: the built-in brightness slider dims and brightens the built-in screen (#1 set path), and the slider keeps its value after a relaunch (#5).

- Second batch (#6–#14, minor), Debug build: a live DDC read passes the new validation (70/100). Saved adjustments on the built-in display produce the expected tables: contrast +50 → 0 / .126 / .503 / .879 / 1, gain +50 → 0 / .376 / .753 / 1 / 1, invert → 1 / .749 / .498 / .247 / 0, paused → profile curve. A stale 60% dimming factor on the DDC monitor was cleared at launch and never applied. Auto Brightness still drives the monitor over DDC. Both displays' tables are back to normal after quitting. Profile restore (probe): re-assigning the display's current profile (factory or a custom sRGB) brought a dimmed table back to the profile curve and kept the custom profile; a table written right after a re-assign is not overwritten by ColorSync.

Not tested at runtime: sleep suppression and wake re-apply (#4, #7), #2, the DDC failure path (this monitor answers DDC), #11/#14 (would move your menu bar and Dock), #12 (this monitor already has an override), and the menu-only items (Image Adjustments close/reset/pause, virtual display Turn On/Off, presets, Launch at Login, Auto Brightness toggle). The menu can't be driven because computer use can't target a menu-bar-only app. Everything else is still open.

**Status labels**
- **Confirmed (probe):** reproduced with a probe program on the real system.
- **Confirmed (state):** visible in the installed app's saved settings (`defaults read com.freedisplay.app`).
- **Confirmed (grep):** proven by searching the code.
- **Code reading:** follows from the code but not reproduced at runtime.

---

## High impact

### 1. Built-in display brightness does nothing on Apple Silicon — Confirmed (probe)
`FreeDisplay/Services/BrightnessService.swift:427-561`

Getting and setting built-in brightness finds the display through `CGDisplayIOServicePort` and falls back to the `IODisplayConnect` services. On Apple Silicon the port is 0 for every display and there are no `IODisplayConnect` services. The built-in slider, the combined slider and the smooth fade only change the UI.

The IOKit fallback in `AutoBrightnessService.swift:76-90` and `HiDPIService.triggerDisplayReenumeration` (`HiDPIService.swift:147-185`) are also no-ops on this hardware.

Probe output:
```
display 1 builtin=1 servicePort=0
display 2 builtin=0 servicePort=0
IODisplayConnect services: 0
CoreDisplay_Display_GetUserBrightness: true
CoreDisplay_Display_SetUserBrightness: true
```
**Fix:** use `CoreDisplay_Display_SetUserBrightness` / `GetUserBrightness` via `dlsym`. This adds a new private API, so per CLAUDE.md it needs the owner's approval.

### 2. Virtual displays can stop auto-creating — Confirmed (probe)
`FreeDisplay/Services/VirtualDisplayService.swift:220-236`

`virtualDisplayAlreadyExists` treats any display whose service port is 0 as virtual. On Apple Silicon physical displays also return 0. A real monitor running at the same size as a saved virtual display config (for example 1920×1080) silently blocks auto-create. A crashed process's virtual display doesn't outlive the process.
**Fix:** remove the check, or match on the virtual vendor ID `0xEEEE` (`CGDisplayVendorNumber`).

### 3. Auto Brightness doesn't start after a relaunch — Confirmed (grep)
`FreeDisplay/Views/AutoBrightnessView.swift:5`

`AutoBrightnessService.shared` is only referenced from `AutoBrightnessView`, so the singleton (and its polling) is created only when the user expands the Auto Brightness section. A saved "enabled" setting does nothing after a relaunch until then.
**Fix:** touch `AutoBrightnessService.shared` at launch in `AppDelegate.applicationDidFinishLaunching`.

### 4. Resolution changes made in System Settings are undone on wake — Confirmed (grep + state)
`FreeDisplay/Services/ResolutionService.swift:27-43`

On wake, the last mode set in FreeDisplay is reapplied whenever it differs from the current mode. `clearSavedModeID` is never called, so a later change in System Settings is reverted on every wake. The saved modes are also stored under display IDs, which change between sessions. Saved state on the test Mac: `fd.ResolutionService.savedModes = { 2 = 58; 3 = 58; }`.
**Fix:** save by `displayUUID`, and clear or update the saved mode when the mode changes outside the app (`setModeFlag` in the reconfiguration callback).

### 5. Brightness always shows 50% after a relaunch — Confirmed (grep + state)
`FreeDisplay/Models/DisplayInfo.swift:57`, `FreeDisplay/Services/SettingsService.swift:81`

`SettingsService.setBrightness` is never called, so `fd.brightness_*` keys never exist (none on the test Mac). Every display starts at 50%. For software-dimmed displays the slider shows 50% while the saved gamma dimming is still reapplied.
**Fix:** save brightness after each change, and set `display.brightness` from the software dimming level when it's reapplied.

### 6. Closing Image Adjustments can wipe the ICC profile and software dimming — Code reading
`FreeDisplay/Views/ImageAdjustmentView.swift:122-141`, `FreeDisplay/Services/GammaService.swift:125-142`

If all sliders are at 0 when the view disappears, `onDisappear` calls `resetSingleDisplay`. That function:
- resets the gamma table to identity, which drops software-brightness dimming, and
- removes the custom ColorSync profile, so the profile picked in Color Profile is lost.

The section's expanded state is saved, so if `onDisappear` also fires when the menu window closes, this happens on every close (not yet checked at runtime). "Reset All" does the same, and "Pause" (`applyIdentity`) also drops the dimming.
**Fix:** split "reset gamma" from "reset ICC profile", only reset when something was actually adjusted, and reapply software dimming afterwards.

### 7. One DDC failure switches a monitor to software dimming until it's unplugged — Code reading (supporting state)
`FreeDisplay/Services/BrightnessService.swift:186-188, 241, 323`

A single failed read or write sets `ddcAvailable[id] = false`, and nothing tries DDC again (not on wake either). Failures are common right after hot-plug or wake, before the monitor answers. Supporting evidence: `fd.softBrightness_2 = 1` exists on the test Mac, so display 2 went through the software path at some point.
**Fix:** count consecutive failures, and re-probe on wake and reconnect before falling back.

### 8. Monitors that use DDC can end up dimmed twice — Code reading
`FreeDisplay/Services/BrightnessService.swift:408-418`, `FreeDisplay/Services/GammaService.swift:206`

The saved software dimming level `fd.softBrightness_<id>` is reapplied on every wake and hot-plug, even when the display now uses DDC. `GammaService.applyFormula` also multiplies it in. It's never cleared, and it's stored under an unstable display ID.
**Fix:** reset it to 1.0 when a DDC write succeeds, and store it by `displayUUID`.

### 9. Auto-brightness and presets leave the slider stale, so brightness keys jump — Code reading
`FreeDisplay/Services/BrightnessService.swift:212-251`, `FreeDisplay/Services/BrightnessKeyService.swift:230`

For external displays, `setBrightness` never updates `display.brightness`. Auto-brightness and presets change the monitor but not the model, and the next brightness key press steps from the old value. Separately, key presses in quick succession step from the middle of a running fade, so each step comes out smaller than 6.25%.
**Fix:** set `display.brightness` in `setBrightness`, and step from the fade's target value instead of its current value.

### 10. Positive Contrast and positive Gain have no effect — Code reading (deterministic math)
`FreeDisplay/Services/GammaService.swift:241-260`

Example, Contrast +50: shift = 50/250 = 0.2, lo = -0.2 → clamped to 0, hi = 1.0 + 0.2 = 1.2 → clamped to 1. The curve doesn't change. Positive Gain is clamped back to 1 the same way. The clamping is also one-sided: with Invert on, or with Gain at -100 and negative Contrast, values outside 0–1 reach `CGSetDisplayTransferByFormula`.
**Fix:** use a table that stretches the curve (an S-curve for contrast), and clamp both ends after inversion.

### 11. "Set as Main Display" rearranges the monitors — Code reading
`FreeDisplay/Services/ArrangementService.swift:38-68`

It puts the target at (0,0) and the old main display at the target's old position, swapping them instead of shifting every display by `-target.origin`. With two displays the layout ends up mirrored; with three or more, the other displays aren't moved. Also, `arrangeExternalAboveBuiltin` puts every external display at the same spot (`DisplayManager.swift:226-230`).
**Fix:** inside one configuration transaction, move every display to `origin - target.origin`.

### 12. Unrequested admin password prompts — Code reading
`FreeDisplay/Services/DisplayManager.swift:125-159`

Every launch and every connect of a 2K+ external display without an override file triggers the administrator prompt. If the user turns HiDPI off or cancels the prompt, it asks again next time. On the test Mac the external display already has its override (`Overrides/DisplayVendorID-1e6d/DisplayProductID-5c4c`), so this doesn't happen there right now.
**Fix:** remember that the user opted out for that vendor and product, and ask before enabling.

### 13. DDC replies aren't checked — Code reading
`FreeDisplay/Services/DDCService.swift:361-380` (also the Intel path at `:593-598`)

`arm64Read` doesn't check the reply opcode (`0x02`), the result code, the echoed VCP code or the checksum. A garbage or "unsupported" reply, such as all 0xFF, reads as max = 65535. That marks DDC as working (`BrightnessService.swift:176-181`), and every later brightness write is scaled to that range.
**Fix:** check the reply fields and checksum, and treat a failed check as a failed read.

### 14. Display bounds go stale — Code reading
`FreeDisplay/Services/DisplayManager.swift:14, 181-192`

Resolution or main-display changes don't refresh `bounds`/`pixelWidth`, and moves (`.movedFlag`) aren't listened for at all. Dragging in Arrange Displays (`ArrangementView.swift:172`), auto-arrange and preset capture use these old values. `MainDisplayView` also doesn't call `refreshDisplays()` after a successful change.
**Fix:** refresh bounds in `refreshExistingDisplayModes` and also react to `.movedFlag`.

---

## Minor

- **Auto Brightness toggle gets stuck on:** if the built-in display is unavailable (lid closed) or at 0 brightness, the toggle is disabled while it's on, so it can't be turned off. `Views/AutoBrightnessView.swift:9-11, 30`
- **Inactive virtual displays can't be turned on:** a saved config that isn't running has no "create" button, only Delete. `Views/VirtualDisplayView.swift:99-153`
- **All virtual displays share one identity:** every virtual display uses vendor `0xEEEE` / product `1` / serial `1`, which can clash when there's more than one. `Services/VirtualDisplayService.swift:94-96`
- **Wrong "Current" preset:** `currentPresetMatch` ignores HiDPI, so "Native" shows as current even in HiDPI mode, and user presets never show "Current" when a built-in preset also matches. `Services/PresetService.swift:173-186`
- **Launch at Login:** the toggle saves the new value even when `register()` fails or needs approval. `Views/MenuBarView.swift:346-355`
- **Software brightness written from two threads:** it's written both from a background queue (`BrightnessService.swift:218`) and from the main thread, so an older write can land last. Both paths also write the gamma table directly instead of going through GammaService, which breaks the project rule that GammaService is the only gamma writer (`BrightnessService.swift:370, 387`).
- **Unused setting:** `ddcCacheTTL` is saved but never read; the DDC cache is hard-coded to 5 seconds (`DDCService.swift:32`).
- **Dead code:** `MirrorService`, `ResolutionSliderView` and `SystemColorView` are no longer used anywhere.

---

## Not yet tested at runtime

These need the menu UI to be driven. `osascript` lacked Accessibility permission during the review:
- #6: whether `onDisappear` fires when the menu window closes.
- #9: stale slider after brightness key presses.
- #14: stale bounds after a resolution change.
