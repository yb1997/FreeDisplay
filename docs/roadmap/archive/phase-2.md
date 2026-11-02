# Phase 2: Brightness control (DDC + built-in) ✅

> Core value: the most-used feature — a brightness slider that controls external and built-in displays

## Task list

- [x] Implement low-level DDC/CI I2C communication (`FreeDisplay/Services/DDCService.swift`)
  - Implementation hints:
    1. Find the I2C port with `IOServiceGetMatchingServices` + `IOFramebufferI2CInterface`
    2. Map `CGDirectDisplayID` → `IOServicePortFromCGDisplayID` to the I2C service
       (requires walking the IOKit registry to match the display vendorID/productID)
    3. Open the I2C connection: `IOI2CInterfaceOpen`
    4. Build DDC/CI read/write requests:
       - Write: address 0x37, prefix 0x51 0x80+len, VCP opcode 0x03 (set) + VCP code + value
       - Read: first write the request (opcode 0x01 get + VCP code), then read the response and parse the current/max value
    5. Close the connection: `IOI2CInterfaceClose`
    6. Key function signatures:
       `func read(displayID: CGDirectDisplayID, command: UInt8) -> (current: UInt16, max: UInt16)?`
       `func write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool`
    7. Add error handling and a retry mechanism (DDC communication is unreliable; retry 3 times at 50 ms intervals)
    Note: DDC communication must run on a background thread so it doesn't block the UI.
    Use the DDC implementation in the open-source MonitorControl project as a reference.
  - Verification: `DDCService.shared.read(displayID: externalID, command: 0x10)` returns the current brightness

- [x] Implement built-in display brightness control (`FreeDisplay/Services/BrightnessService.swift`)
  - Implementation hints:
    The built-in display doesn't use DDC. Use `IODisplaySetFloatParameter` + `kIODisplayBrightnessKey`.
    Get: `IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey, &brightness)`
    Set: `IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey, brightness)`
    Get the service with `IOServiceGetMatchingService` + `IODisplayConnect`.
    The value range is 0.0-1.0 and must be converted to a percentage for display.
  - Verification: after the code changes the brightness value, the built-in display's brightness actually changes

- [x] Implement the brightness slider UI (`FreeDisplay/Views/BrightnessSliderView.swift`)
  - Implementation hints:
    A horizontal Slider with a sun icon (☀) on the left and the percentage on the right.
    Modeled on the layout of the "Brightness (Combined)" area in the BetterDisplay screenshots.
    `@Binding var brightness: Double` (0-100).
    Call DDCService/BrightnessService from the Slider's `onEditingChanged` callback.
    Add a debounce (200 ms) to avoid frequent DDC communication.
    Support a "combined brightness" mode: one slider controls the brightness of every display at once (mapped proportionally).
  - Verification: dragging the slider actually changes the external display's brightness

- [x] Integrate brightness control into the menu (`FreeDisplay/Views/MenuBarView.swift`)
  - Implementation hints:
    Add a "Brightness (Combined)" area below the display list, containing a combined brightness slider.
    Each display also has its own brightness slider when expanded.
    Add a `brightness: Double` property to `DisplayInfo`, initialized with a DDC read at launch.
  - Verification: the menu shows brightness sliders, and dragging them changes the display brightness

## Phase acceptance

- DDC brightness reading and setting work correctly for the external display
- Brightness reading and setting work correctly for the built-in display
- The UI slider drags smoothly with no noticeable lag
- Combined brightness mode can control multiple screens at once

**When done**: running project-optimize to reflect is recommended
