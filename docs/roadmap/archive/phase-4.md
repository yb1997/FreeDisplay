# Phase 4: Screen rotation and display arrangement ✅

> Core value: screen rotation and spatial arrangement of multiple displays

## Task list

- [x] Implement screen rotation (`FreeDisplay/Services/RotationService.swift`)
  - Implementation hints:
    Use `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin` together with rotation.
    macOS rotation is set through IOKit:
    ```swift
    IOServiceRequestProbe(service, kIOFBSetTransform)  // triggers rotation
    ```
    Or get the current rotation angle with `CGDisplayRotation()`,
    and set the rotation with the private API `CGSConfigureDisplayMode`.
    Alternative: follow the approach of the `displayplacer` CLI tool and operate directly through IOKit.
    Supported angles: 0°, 90°, 180°, 270°.
  - Verification: after choosing 90° rotation, the display image actually rotates

- [x] Implement the screen rotation UI (`FreeDisplay/Views/RotationView.swift`)
  - Implementation hints:
    An expandable "Screen Rotation" section.
    Four options: rotate the screen 90°/180°/270° + turn off rotation.
    One row per option, with a rotation-direction arrow icon on the left (↻/↓/←) and text on the right.
    Highlight the current rotation state.
    Modeled on the screen rotation area layout in the BetterDisplay screenshots.
  - Verification: the UI shows four rotation options, and clicking one actually rotates the screen

- [x] Implement display arrangement (`FreeDisplay/Services/ArrangementService.swift`)
  - Implementation hints:
    Use `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin(config, displayID, x, y)`
    → `CGCompleteDisplayConfiguration` to set the display's position on the virtual desktop.
    Get the current position: the origin returned by `CGDisplayBounds(displayID)`.
    Multi-display coordinate system: the main display's top-left corner is (0,0), and other displays are offset relative to it.
  - Verification: after the code adjusts a display's position, the arrangement in System Settings actually changes

- [x] Implement the display arrangement UI (`FreeDisplay/Views/ArrangementView.swift`)
  - Implementation hints:
    An expandable "Arrange Displays" section.
    The content is a grid view, modeled on the BetterDisplay screenshots:
    display thumbnails (blue rectangle + name) on a gray background, which can be dragged.
    Implement dragging with SwiftUI's `.gesture(DragGesture())`.
    Scale the display rectangles proportionally to their actual resolutions.
    When a drag ends, call ArrangementService to update the position.
    Use a light gray checkered grid background to represent the extent of the virtual desktop.
  - Verification: the display arrangement view matches the BetterDisplay screenshot layout, and dragging updates the position

- [x] Set as main display feature (`FreeDisplay/Services/DisplayManager.swift` extension)
  - Implementation hints:
    Add `func setAsMainDisplay(_ displayID: CGDirectDisplayID)` to DisplayManager.
    Use `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin(config, displayID, 0, 0)`
    to move the target display to the origin (on macOS, the main display = the display at the coordinate origin).
    Adjust the other displays' coordinates accordingly.
  - Verification: after setting it as the main display, the Dock and menu bar move to the target display

## Phase acceptance

- Screen rotation works correctly in all four directions
- Visual drag-and-drop display arrangement works correctly
- The set as main display feature works correctly
- The UI layout matches the BetterDisplay screenshots

**When done**: running project-optimize to reflect is recommended
