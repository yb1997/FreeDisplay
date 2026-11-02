# Phase 3: Resolution management and HiDPI ✅

> Core value: resolution switching and HiDPI support, BetterDisplay's core selling point

## Task list

- [x] Implement display mode enumeration (`FreeDisplay/Models/DisplayMode.swift`)
  - Implementation hints:
    Model properties: `width: Int`, `height: Int`, `refreshRate: Double`, `bitDepth: Int`,
    `isHiDPI: Bool`, `isNative: Bool`, `ioDisplayModeID: Int32`.
    Get every mode with `CGDisplayCopyAllDisplayModes(displayID, options)`.
    Add `kCGDisplayShowDuplicateLowResolutionModes: true` to the options dictionary to show HiDPI modes.
    Get the current mode with `CGDisplayCopyDisplayMode(displayID)`.
    Detecting HiDPI: it's HiDPI when `CGDisplayModeGetPixelWidth > CGDisplayModeGetWidth`.
    Display format modeled on BetterDisplay: `1470x956` + tags (notch/60Hz/10bit).
  - Verification: can list every mode of the built-in display, including 1470x956 (HiDPI), 2560x1664 (native), etc.

- [x] Implement resolution switching (`FreeDisplay/Services/ResolutionService.swift`)
  - Implementation hints:
    ```swift
    func setDisplayMode(_ mode: CGDisplayMode, for displayID: CGDirectDisplayID) -> Bool
    ```
    Switch in three steps: `CGBeginDisplayConfiguration` → `CGConfigureDisplayWithDisplayMode` →
    `CGCompleteDisplayConfiguration(.permanently)`.
    Save the current mode before switching, and roll back on failure.
    Note: switching HiDPI modes may require the private API `CGSConfigureDisplayMode`,
    or injecting HiDPI modes by creating a custom timing (covered in depth in the Phase 10 virtual display work).
  - Verification: after switching, the display's actual resolution changes

- [x] Implement the resolution slider UI (`FreeDisplay/Views/ResolutionSliderView.swift`)
  - Implementation hints:
    Modeled on the resolution area in the BetterDisplay screenshots: a horizontal Slider + the current resolution text on the right.
    The Slider's steps correspond to indexes in the list of available modes.
    A small display icon on the left, `1470x956` text on the right.
    Preview the resolution text live while dragging, and switch on release.
  - Verification: dragging the slider changes the displayed resolution text

- [x] Implement the display mode list UI (`FreeDisplay/Views/DisplayModeListView.swift`)
  - Implementation hints:
    An expandable "Display Modes" section (modeled on the BetterDisplay screenshot layout).
    Two groups:
    1. "Default and native modes": the native resolution + the system default HiDPI modes
    2. "Modes matching the default filter": other available modes
    One row per mode: icon (●/◉/⊙) + resolution text + tags on the right (notch/60Hz/10bit).
    Highlight the currently selected mode (blue circle icon).
    Click to switch.
    Add a "Favorites" feature and a "Filter..." button (like the ☆ management and ⊙ filter in the screenshots).
  - Verification: the display mode list matches the BetterDisplay screenshot layout

- [x] HiDPI mode injection (`FreeDisplay/Services/HiDPIService.swift`)
  - Implementation hints:
    External displays don't offer HiDPI modes by default. They have to be enabled in one of these ways:
    1. Use `CGVirtualDisplay` to create a virtual display matching the external resolution (recommended, completed in Phase 10)
    2. Or modify the IOKit display override plist to inject custom resolutions
       Path: `/System/Library/Displays/Contents/Resources/Overrides/`
       Format: `DisplayVendorID-XXXX/DisplayProductID-XXXX`
    Phase 3 implements option 2 (plist override) first; Phase 10 then enhances it with the virtual display approach.
    Note: macOS SIP protects system directories, so the user must be guided to disable SIP, or a user-level override must be used.
  - Verification: the external display shows HiDPI scaled modes it didn't have before

## Phase acceptance

- The resolution mode lists of the built-in and external displays show completely
- Clicking an item in the mode list switches the resolution successfully
- The resolution slider works correctly
- The display mode list UI matches the BetterDisplay style

**When done**: running project-optimize to reflect is recommended
