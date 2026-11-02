# Roadmap — FreeDisplay

> Created: 2026-03-02 | Goal: a free macOS display management menu bar app that fully replaces BetterDisplay
> **For detailed implementation hints, see**: `docs/roadmap/phase-N.md`

## Archived phases (0-17)

> Details: `docs/roadmap/archive/`

- Phase 0: Project initialization ✅
- Phase 1: Display detection and menu UI ✅
- Phase 2: Brightness control (DDC + built-in) ✅
- Phase 3: Resolution management and HiDPI ✅
- Phase 4: Screen rotation and display arrangement ✅
- Phase 5: Color management ✅
- Phase 6: Image adjustments ✅
- Phase 7: Advanced display management ✅
- Phase 8: Screen mirroring ✅
- Phase 9: Screen streaming and picture-in-picture ✅
- Phase 10: Virtual displays ✅
- Phase 11: Configuration protection and auto brightness ✅
- Phase 12: Wrap-up and release ✅
- Phase 13: Critical bug fixes ✅
- Phase 14: Performance optimization (eliminating stutter) ✅
- Phase 15: Interaction polish ✅
- Phase 16: Comprehensive bug fixes ✅
- Phase 17: Targeted core feature fixes — DDC/HiDPI/notch ✅

## Phase 18: Stability hardening ✅
> Details: `docs/roadmap/phase-18.md`

### Task 1: Unified timeout protection for blocking CG calls
- [x] Extract VirtualDisplayService's `runWithTimeout` into a shared utility function
- [x] MirrorService: add timeout protection to `enableMirror`/`disableMirror`
- [x] ArrangementService: add timeout protection to `setPosition`
- [x] ResolutionService: add 10-second timeout protection to `applyModeSync`

### Task 2: Automatic re-arrangement after display configuration changes
- [x] Register `CGDisplayRegisterReconfigurationCallback`
- [x] After a configuration change completes, call `arrangeExternalAboveBuiltin()` after a 500 ms delay
- [x] Debounce mechanism (multiple callbacks within 500 ms run only the last one)

### Task 3: Automatically restore HiDPI after sleep/wake
- [x] On wake, check for an active HiDPI session and recreate it if lost
- [x] Restore sequence: create → apply settings → sleep 500 ms → mirror → setDisplayMode → arrange
- [x] Persist HiDPI state to UserDefaults (`fd.hiDPI.activePhysicalIDs`)

### Task 4: Error recovery and user feedback
- [x] Show a menu bar status hint when a CG call times out
- [x] Prompt the user to turn HiDPI back on manually when HiDPI restore fails
- [x] Automatically disable HiDPI and notify the user after 3 consecutive failures

## Phase 19: Display preset system ✅
> Details: `docs/roadmap/phase-19.md`

### Task 1: Preset data model
- [x] Create `Models/DisplayPreset.swift`
- [x] Create `Services/PresetService.swift`: load/save/apply presets
- [x] Store presets in `~/Library/Application Support/FreeDisplay/presets.json`

### Task 2: Built-in default presets
- [x] "HiDPI Mode": enableHiDPIVirtual + 1920×1080 + arrangement
- [x] "Native Mode": disable the HiDPI virtual display + restore the native resolution + arrangement
- [x] Built-in presets can't be deleted (`isBuiltin: true`)

### Task 3: Save the current state as a preset
- [x] Add a "Save as Preset" button to the menu bar
- [x] Inline form: enter a name, choose an icon
- [x] Automatically capture and save the current state of every display

### Task 4: Preset list and one-click switching
- [x] Show the preset list in MenuBarView (in place of HiDPIPresetRow)
- [x] Each preset shows an icon + name + current-match badge
- [x] Click a preset → apply it (loading spinner)
- [x] Long-press/right-click → delete (non-built-in presets)

## Phase 20: Release preparation ✅
> Details: `docs/roadmap/phase-20.md`

### Task 1: App icon
- [x] Design a display icon and generate every size in AppIcon.appiconset
- [x] Update project.yml to reference AppIcon

### Task 2: Launch at Login improvements
- [x] Confirm `SMAppService.mainApp` is used (macOS 13+)
- [x] On first launch, ask the user whether to launch at login

### Task 3: DMG packaging
- [x] Create the `scripts/build-dmg.sh` script
- [x] Release build + DMG packaging (FreeDisplay.app + Applications shortcut)

### Task 4: GitHub Release
- [x] Add feature screenshots to README.md
- [x] Add CHANGELOG.md
- [x] `scripts/release.sh`: build → package DMG → gh release create

### Task 5: UpdateService improvements
- [x] Confirm the update check logic points at the GitHub Releases API
- [x] Show a download link when a new version is detected
- [x] Confirm the "Check for Updates at Launch" toggle works
