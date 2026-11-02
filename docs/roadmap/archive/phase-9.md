# Phase 9: Screen streaming and picture-in-picture ✅

> Core value: BetterDisplay's most advanced features — streaming a screen to a window + a floating picture-in-picture window

## Task list

- [x] Implement the screen capture engine (`FreeDisplay/Services/ScreenCaptureService.swift`)
  - Implementation hints:
    Use ScreenCaptureKit (macOS 12.3+):
    ```swift
    import ScreenCaptureKit

    // 1. Get the shareable content
    let content = try await SCShareableContent.current
    let display = content.displays.first { $0.displayID == targetDisplayID }

    // 2. Create the filter and configuration
    let filter = SCContentFilter(display: display!, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = Int(display!.width)
    config.height = Int(display!.height)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60fps
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = true

    // 3. Create and start the stream
    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
    try await stream.startCapture()
    ```
    Output `CMSampleBuffer` → convert to `CIImage` → pass to the view layer for rendering.
    Needs the Screen Recording permission: an authorization dialog appears on first use.
  - Verification: after capture starts, frames of the display image are received

- [x] Implement the stream window (`FreeDisplay/Views/StreamWindow.swift`)
  - Implementation hints:
    Create a standalone NSWindow to show the captured image:
    - `NSWindow(contentRect:, styleMask: [.titled, .closable, .resizable], ...)`
    - Render the CMSampleBuffer content with high performance using a `MetalView` (MTKView) or `CAMetalLayer`
    - Or convert from CIImage with a SwiftUI `Image` (lower performance, but simple)
    The Metal rendering path is recommended:
    ```swift
    class MetalStreamView: MTKView {
        // Render CMSampleBuffer → CVPixelBuffer → MTLTexture
    }
    ```
    Window support: scale the content proportionally when the window is resized.
  - Verification: the stream window shows the target display's image in real time

- [x] Implement streaming options (`FreeDisplay/ViewModels/StreamViewModel.swift`)
  - Implementation hints: modeled on the screen streaming area in the BetterDisplay screenshots, implement these options:
    - Show mouse pointer: `config.showsCursor = true/false`
    - 1:1 pixel mapping: window size = capture resolution
    - Integer scaling: the window's width and height can only be integer multiples/fractions of the capture resolution
    - Free aspect ratio: allow non-proportional scaling
    - Video filters: process frames with CIFilter (grayscale, blur, sharpen, etc.)
    - Enable cropping: show only part of the captured image in the window (the user can drag a crop frame)
    - Flip (horizontal/vertical): CIFilter `CIAffineTransform`
    - Rotate (0°/90°/180°/270°): CIFilter `CIAffineTransform`
    - Scale slider (0.1x~4.0x)
    - Underscan slider (percentage of the edges to crop)
    - Opacity slider (`window.alphaValue`)
    - "Resume streaming when connected": persisted in UserDefaults
  - Verification: switching each option actually changes the streamed image

- [x] Implement picture-in-picture (`FreeDisplay/Views/PiPWindow.swift`)
  - Implementation hints:
    Picture-in-picture = a smaller floating stream window + extra control options.
    Extend StreamWindow and add:
    - Window level: normal level / above other windows / above the menu bar
      `window.level = .normal / .floating / .statusBar + 1`
    - Show/hide the title bar: `window.styleMask.insert/remove(.titled)`
    - Not movable: `window.isMovable = false`
    - Disallow resizing: `window.styleMask.remove(.resizable)`
    - Snap to 25% increments: after a drag ends, snap to the nearest 25% of the screen width
    - Mouse click-through: `window.ignoresMouseEvents = true`
    - Window shadow: `window.hasShadow = true/false`
    - Exclude the PiP window (so it isn't captured by itself): the `excludingWindows` parameter of ScreenCaptureKit
  - Verification: the PiP window floats above other windows, and every option works

- [x] Implement the streaming/PiP menu UI (`FreeDisplay/Views/StreamControlView.swift`, `PiPControlView.swift`)
  - Implementation hints:
    Two expandable sections, "Screen Streaming" and "Picture in Picture", modeled on the BetterDisplay screenshots.
    Streaming area: target selection list + stop button + every option toggle/slider
    Picture-in-picture area: enable/autostart + level selection + every option toggle/slider + a flip/rotate button group
    Bottom buttons: "Add Stream Configuration"/"Add Picture in Picture Setup" (supports multiple streams/PiPs running at the same time)
  - Verification: the UI matches the BetterDisplay screenshots exactly

## Phase acceptance

- Screen streaming shows the target display's image in real time with a smooth frame rate
- Every streaming option (mouse, scaling, rotation, cropping, filters, opacity) works
- The picture-in-picture floating window stays on top, and every PiP option works
- Multiple streams/PiPs can run at the same time
- The UI matches the BetterDisplay screenshots

**When done**: running project-optimize to reflect is recommended
