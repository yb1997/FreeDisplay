# Phase 11: Configuration protection and auto brightness ✅

> Core value: prevent the system from resetting display settings + ambient-light auto brightness

## Task list

- [x] Implement configuration snapshots (`FreeDisplay/Services/ConfigProtectionService.swift`)
  - Implementation hints:
    Save a snapshot of the current display's complete configuration:
    ```swift
    struct DisplayConfig: Codable {
        let displayID: UInt32
        let displayName: String
        let resolution: (width: Int, height: Int)
        let refreshRate: Double
        let rotation: Int
        let colorProfile: String
        let brightness: Double
        let contrast: Double
        let hdrEnabled: Bool
        let isMain: Bool
        let isMirrored: Bool
        let mirrorSource: UInt32?
        let origin: CGPoint
    }
    ```
    Store snapshots in `~/Library/Application Support/FreeDisplay/configs/` as JSON.
    Support multiple named snapshots ("Daytime configuration", "Nighttime configuration", etc.).
  - Verification: after saving a snapshot, the JSON file is generated correctly

- [x] Implement configuration protection monitoring (`ConfigProtectionService` extension)
  - Implementation hints:
    Modeled on the "Configuration Protection" section in the BetterDisplay screenshots, with selectable protected items:
    - Resolution, refresh rate, color mode, HDR color mode, rotation,
      color profile, HDR color profile, HDR status, mirroring, main display status
    Listen for display configuration changes with `CGDisplayRegisterReconfigurationCallback`.
    When a protected item is detected as changed, restore it to the snapshot value automatically.
    Shortcut buttons to enable/disable all protection.
  - Verification: with resolution protected, changing the resolution from System Settings is reverted automatically

- [x] Implement the configuration protection UI (`FreeDisplay/Views/ConfigProtectionView.swift`)
  - Implementation hints:
    An expandable "Configuration Protection" section, modeled on the screenshots:
    A list of protected items, one Toggle per row:
    Resolution (📺) / Refresh Rate (📡) / Color Mode (🎨) / HDR Color Mode / Rotation (🔄) /
    Color Profile (🎯) / HDR Color Profile / HDR Status / Mirroring (📋) / Main Display Status (Ⓜ)
    At the bottom:
    - Two buttons, "Enable All Protection" / "Disable All Protection"
    - Explanatory text: "Settings made by this application are protected."
  - Verification: the UI matches the BetterDisplay screenshots

- [x] Implement auto brightness (`FreeDisplay/Services/AutoBrightnessService.swift`)
  - Implementation hints:
    The macOS built-in display has an ambient light sensor.
    Read the ambient light: `IOServiceGetMatchingService` + `AppleLMUController` to read the lux value.
    Or get ambient light data with `CBTrueToneClient` (a private framework).
    Simplified approach: use the `IOReport` framework, or read the IOKit ambient light sensor value.
    Brightness mapping curve: a logarithmic lux → brightness mapping, where the user can adjust the curve's offset.
    Auto brightness for external displays: adjust them in sync with the built-in sensor's value (through DDC).
    Settings options: an "Auto Brightness" Toggle + a sensitivity slider.
  - Verification: covering the ambient light sensor lowers the screen brightness automatically

- [x] Implement the auto brightness UI (`FreeDisplay/Views/AutoBrightnessView.swift`)
  - Implementation hints:
    Add an "Auto Brightness" option (blue Ⓐ icon) at the bottom of the menu or in the display details, modeled on the screenshots.
    A Toggle switch + an optional sensitivity slider.
  - Verification: the toggle works, and brightness changes with the ambient light

## Phase acceptance

- Every configuration protection item works
- Protected configuration is restored automatically after the system changes it
- Auto brightness follows changes in ambient light
- Every setting is persisted (takes effect after restart)

**When done**: running project-optimize to reflect is recommended
