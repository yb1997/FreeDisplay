# Phase 10: Virtual displays ✅

> Core value: create dummy displays / virtual screens, and extend HiDPI support

## Task list

- [x] Implement virtual display creation (`FreeDisplay/Services/VirtualDisplayService.swift`)
  - Implementation hints:
    Use the `CGVirtualDisplay` API on macOS 14+:
    ```swift
    import CoreGraphics

    let descriptor = CGVirtualDisplayDescriptor()
    descriptor.queue = DispatchQueue.global()
    descriptor.name = "FreeDisplay Virtual"
    descriptor.maxPixelsWide = 3840
    descriptor.maxPixelsHigh = 2160
    descriptor.sizeInMillimeters = CGSize(width: 600, height: 340) // 27 inch
    descriptor.productID = 0x1234
    descriptor.vendorID = 0x5678
    descriptor.serialNum = 0

    let display = CGVirtualDisplay(descriptor: descriptor)

    // Add display modes
    let settings = CGVirtualDisplaySettings()
    settings.hiDPI = 1  // enable HiDPI
    let mode = CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)
    settings.modes = [mode, ...]
    display?.applySettings(settings)
    ```
    Features:
    - Create a virtual display (with a given name, resolution, and DPI)
    - Destroy a virtual display
    - List the currently active virtual displays
    - Persist the configuration (UserDefaults/JSON) and create them automatically at launch
    Note: once a virtual display is created, the system treats it as a real display, so it can be used for HiDPI and Sidecar scenarios.
  - Verification: after creating a virtual display, a new display appears in System Settings

- [x] Implement HiDPI enhancement (based on virtual displays) (`HiDPIService` extension)
  - Implementation hints:
    Phase 3 implemented HiDPI with a plist override; here, enhance it with the virtual display approach:
    1. Create a virtual display that matches the external display's resolution (with HiDPI enabled)
    2. Mirror the external display to the virtual display
    3. The external display inherits the virtual display's HiDPI modes
    This is the core of how BetterDisplay implements HiDPI — no system files to modify, no SIP needed.
    Add a "High Resolution (HiDPI)" toggle to ResolutionService that automatically creates the paired virtual display when turned on.
  - Verification: after turning on HiDPI for the external display, scaled modes appear in the resolution list

- [x] Implement the virtual display management UI (`FreeDisplay/Views/VirtualDisplayView.swift`)
  - Implementation hints:
    Add a "Displays and Virtual Screens" entry point to the "Tools" area (modeled on the screenshots).
    Clicking it opens a management panel/window:
    - The list of current virtual displays (name, resolution, status)
    - A "+" button to add a new virtual display (opens a configuration form: name, resolution, DPI)
    - A delete button on each row
    - A persistence option (create automatically on next launch)
  - Verification: the full flow of creating/deleting virtual displays works

- [x] Implement the one-click "High Resolution (HiDPI)" toggle UI
  - Implementation hints:
    Add a "High Resolution (HiDPI)" row (blue ⊕ icon) to each display's menu area, modeled on the screenshots.
    The Toggle controls it: when turned on, it automatically creates the paired virtual display and mirrors it;
    when turned off, it destroys the virtual display and cancels the mirroring.
    The state is persisted to UserDefaults.
  - Verification: after turning on HiDPI, the external display's resolution list changes

## Phase acceptance

- Virtual display creation/destruction works
- HiDPI takes effect through the virtual display approach
- The virtual display management UI is complete
- Configuration persistence works (restored after restart)

**When done**: running project-optimize to reflect is recommended
