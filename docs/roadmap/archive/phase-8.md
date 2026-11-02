# Phase 8: Screen mirroring ✅

> Core value: mirror the content of one display to another display

## Task list

- [x] Implement hardware mirroring (`FreeDisplay/Services/MirrorService.swift`)
  - Implementation hints:
    macOS natively supports hardware-level screen mirroring through the CoreGraphics API:
    ```swift
    func enableMirror(source: CGDirectDisplayID, target: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, target, source)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    func disableMirror(displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
    ```
    Checking whether it's mirroring: `CGDisplayMirrorsDisplay(displayID)` returns the source display ID;
    if it returns `kCGNullDirectDisplay`, the display isn't mirroring.
    Note: hardware mirroring requires the two displays to have compatible resolutions.
  - Verification: after mirroring is enabled, both displays show the same content

- [x] Implement the screen mirroring UI (`FreeDisplay/Views/MirrorView.swift`)
  - Implementation hints:
    An expandable "Screen Mirroring" section, modeled on the BetterDisplay screenshots:
    Text below the title: "Mirror this display's content to:"
    A list of available target displays (e.g. "H2435Q"), each row with a display icon on the left.
    A "Stop Mirroring" button at the bottom (toggling between grayed-out/enabled).
    Mirroring starts immediately after a target is chosen.
  - Verification: choosing a target display starts mirroring, and clicking stop restores the normal state

## Phase acceptance

- Built-in → external mirroring works
- External → built-in mirroring works
- Stopping mirroring restores the normal state
- The UI matches the BetterDisplay screenshots

**When done**: running project-optimize to reflect is recommended
