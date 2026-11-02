# Phase 19: Display preset system

> Status: Complete | Estimate: medium complexity

## Goal

Extend one-click HiDPI into a general display preset system, so users can save the current display state as a preset and switch between configurations with one click.

## Tasks

### Task 1: Preset data model
- [x] Create `Models/DisplayPreset.swift` and define the preset struct:
  - `id: UUID`, `name: String`, `icon: String` (SF Symbol name)
  - `displays: [DisplayPresetEntry]`, where each entry contains:
    - `displayUUID: String` (matches the physical display)
    - `width: Int`, `height: Int`, `isHiDPI: Bool` (target resolution)
    - `brightness: Double?` (optional brightness)
    - `arrangement: CGPoint?` (optional arrangement position)
    - `enableHiDPIVirtual: Bool` (whether to enable the HiDPI virtual display)
- [x] Create `Services/PresetService.swift`: load/save/apply presets
- [x] Store presets in `~/Library/Application Support/FreeDisplay/presets.json`

**Implementation hint**: Match displays with `display.displayUUID` (the stable UUID generation logic already exists). When applying a preset, skip the entry for any display that isn't online.

### Task 2: Built-in default presets
- [x] "HiDPI Mode": reuse the current HiDPIPresetRow logic (enableHiDPIVirtual + 1920×1080 + arrangement)
- [x] "Native Mode": disable the HiDPI virtual display + restore the display's native resolution + arrangement
- [x] Built-in presets can't be deleted; mark them `isBuiltin: true`

**Implementation hint**: Move HiDPIPresetRow's turnOn/turnOff logic into PresetService.applyPreset(), and change HiDPIPresetRow to call PresetService.

### Task 3: Save the current state as a preset
- [x] Add a "Save as Preset" button to the menu bar (below the preset list)
- [x] Clicking it shows an inline form: enter a name, choose an icon
- [x] Automatically capture the resolution, HiDPI state, brightness, and arrangement position of every current display
- [x] Save to presets.json

**Implementation hint**: Follow the inline form pattern of CreateVirtualDisplayForm. For icon selection, use a Picker + a few predefined SF Symbols.

### Task 4: Preset list and one-click switching
- [x] Show the preset list in MenuBarView (replace HiDPIPresetRow's spot with a preset section)
- [x] Each preset shows: icon + name + whether it currently matches (green "Current" badge)
- [x] Click a preset → apply it (show a loading spinner)
- [x] Long-press/right-click → delete (non-built-in presets)

**Implementation hint**: Preset match detection: walk every DisplayPresetEntry and check whether the current resolution and HiDPI state match. If they all match, mark it "Current".

## Acceptance criteria

```bash
# Build passes
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# Manual testing
# 1. Turn on HiDPI → save as preset "Work Mode" → turn off HiDPI → click "Work Mode" → HiDPI comes back
# 2. Switch to 1280×720 → save as preset "Low Resolution" → switch between the two presets
# 3. The built-in "HiDPI Mode" and "Native Mode" can't be deleted
```
