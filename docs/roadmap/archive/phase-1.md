# Phase 1: Display detection and menu UI ✅

> Core value: list every connected display, show basic info, and establish the UI framework

## Task list

- [x] Implement the `DisplayInfo` model (`FreeDisplay/Models/DisplayInfo.swift`)
  - Implementation hint: properties include `displayID: CGDirectDisplayID`, `name: String`,
    `isBuiltin: Bool`, `isMain: Bool`, `isOnline: Bool`, `vendorNumber: UInt32`,
    `modelNumber: UInt32`, `serialNumber: UInt32`, `bounds: CGRect`,
    `pixelWidth: Int`, `pixelHeight: Int`, `rotation: Double`.
    Get them with CG functions such as `CGDisplayIsBuiltin()` / `CGDisplayIsMain()`.
    Get the display name from `kDisplayProductName` in `IODisplayCreateInfoDictionary`.
  - Verification: correctly identifies the names of the built-in display and the H2435Q external display

- [x] Implement the `DisplayManager` detection logic (`FreeDisplay/Services/DisplayManager.swift`)
  - Implementation hint: `@Published var displays: [DisplayInfo]`.
    Get every online display with `CGGetOnlineDisplayList(16, &displayIDs, &count)`.
    Listen with `CGDisplayRegisterReconfigurationCallback` to refresh automatically when displays are hot-plugged.
    Scan once at launch.
  - Verification: the list updates automatically when a display is plugged in or unplugged

- [x] Implement the main menu bar view (`FreeDisplay/Views/MenuBarView.swift`)
  - Implementation hint: a vertical ScrollView with the display list at the top (one row per display, with the name + an on/off Toggle),
    modeled on the layout in the BetterDisplay screenshots: display name on the left, Toggle switch on the right.
    Add an Ⓜ mark after the built-in display's name to indicate the main display.
    Use `@EnvironmentObject var displayManager: DisplayManager`.
    Put a "Tools" section and a "Quit FreeDisplay" button at the bottom.
  - Verification: the menu shows two rows, for the H2435Q and the built-in display

- [x] Implement the display detail expansion area (`FreeDisplay/Views/DisplayDetailView.swift`)
  - Implementation hint: clicking a display row expands its details, using a `DisclosureGroup` or a custom expand animation.
    When expanded, show the feature list (brightness, resolution, etc.), with a section header for each feature.
    In Phase 1, put placeholder text first; later phases implement them one by one.
    Follow the section list style in the BetterDisplay screenshots (blue icon + text + right arrow).
  - Verification: clicking a display row expands it and shows the list of feature sections

- [x] Display on/off feature (`FreeDisplay/Services/DisplayManager.swift`)
  - Implementation hint: a Toggle turns the display on/off. External displays use DDC VCP code 0xD6 (Power Mode)
    to send a standby command. The built-in display uses `IORegistryEntrySetCFProperty` to set brightness to 0.
    Note: full DDC communication is implemented in Phase 2; for now this can be simulated with `CGDisplayCapture` / `CGDisplayRelease`.
  - Verification: turning the Toggle off for the external display makes its screen go black

## Phase acceptance

- After building and running, clicking the menu bar icon opens the panel
- The panel shows every connected display (with correct names)
- Display rows can be expanded to show the placeholder list of feature sections
- There's a working "Quit FreeDisplay" button at the bottom

**When done**: running project-optimize to reflect is recommended
