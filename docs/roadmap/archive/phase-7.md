# Phase 7: Advanced display management ✅

> Core value: main display switching, notch management, integrated control, and display management settings

## Task list

- [x] Implement the "Set as Main Display" UI and logic (`FreeDisplay/Views/MainDisplayView.swift`)
  - Implementation hints:
    Add a "Set as Main Display" option (Ⓜ icon) to the menu, like the blue circled M icon in the screenshots.
    The logic is already implemented in Phase 4's ArrangementService (move to the coordinate origin).
    This task is the UI layer: show an Ⓜ mark next to the current main display in the display list.
    Clicking another display's "Set as Main Display" button switches to it.
  - Verification: after clicking, the Dock and menu bar move to the target display

- [x] Implement "display notch" management (`FreeDisplay/Views/NotchView.swift`)
  - Implementation hints:
    MacBooks have a notch, which affects resolution and layout.
    Feature: tag modes in the resolution list with a "notch" label (like the "notch 60Hz 10bit" in the screenshots).
    Detecting the notch: `NSScreen.safeAreaInsets.top > 0`, or check the device model.
    Provide a "Hide Notch" option: cover the notch area with a black bar
    (create a borderless, always-on-top black NSWindow that covers the notch area).
  - Verification: the "notch" label shows correctly next to the built-in display's resolutions

- [x] Implement "integrated control" (DDC extension) (`FreeDisplay/Views/IntegratedControlView.swift`)
  - Implementation hints:
    An expandable "Integrated Control" section, modeled on the screenshot layout:
    - "Read and Update from Device" button: reads every DDC VCP code and refreshes the UI
    - "Configure Integrated Control Items..." button: opens a configuration window
    DDCService extension: read the common VCP codes in bulk:
    0x10 (brightness), 0x12 (contrast), 0x14 (color temperature preset), 0x16 (video gain R),
    0x18 (video gain G), 0x1A (video gain B), 0x60 (input source), 0x62 (volume),
    0x87 (color saturation), 0xD6 (power mode), 0xDC (display mode)
    Store the results in the `ddcValues: [UInt8: UInt16]` dictionary on DisplayInfo.
  - Verification: after clicking "Read from Device", the external display's DDC parameters show correctly

- [x] Implement the "Manage Display" settings (`FreeDisplay/Views/ManageDisplayView.swift`)
  - Implementation hints:
    An expandable "Manage Display" section, modeled on the screenshots:
    - "Configure Display...": opens the Displays pane of System Settings
      `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings")!)`
    - "Visual Identification": shows a full-screen identification window on the target display (with the display name + ID),
      which closes automatically after 3 seconds. Position it on the target display with NSWindow + NSScreen.
    - Hint text: "Use ⌥ Option + click on a display menu title to identify it quickly."
    - "Prevent Sleep While Connected": create a power assertion with `IOPMAssertionCreateWithName`
      to keep the system from sleeping (`kIOPMAssertionTypePreventSystemSleep`).
  - Verification: after clicking "Visual Identification", the identification window appears on the target display

## Phase acceptance

- Main display switching works correctly
- The notch label shows correctly
- Integrated control can read DDC parameters
- Every subfeature of Manage Display works

**When done**: running project-optimize to reflect is recommended
