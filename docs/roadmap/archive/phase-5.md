# Phase 5: Color management ✅

> Core value: ICC color profile switching and color mode management

## Task list

- [x] Implement ICC profile enumeration (`FreeDisplay/Services/ColorProfileService.swift`)
  - Implementation hints:
    Enumerate the system ICC profiles with the ColorSync framework:
    ```swift
    import ColorSync
    // Get every ICC profile
    let profileIterator = ColorSyncProfileIterateInstalledProfiles()
    ```
    Or scan the ICC profile directories on the file system:
    - `/Library/ColorSync/Profiles/`
    - `/System/Library/ColorSync/Profiles/`
    - `~/Library/ColorSync/Profiles/`
    Get the current display's profile: `CGDisplayCopyColorSpace(displayID)` →
    get the name with `CGColorSpace.name`.
    Profile model: `name: String`, `path: URL`, `colorSpace: String` (RGB/CMYK, etc.).
  - Verification: can list every ICC profile on the system, including Display P3, sRGB, Adobe RGB, etc.

- [x] Implement ICC profile switching (`ColorProfileService` extension)
  - Implementation hints:
    Set the profile for a given display with the ColorSync API:
    ```swift
    ColorSyncDeviceSetCustomProfiles(
      kColorSyncDisplayDeviceClass,
      deviceID,  // CGDirectDisplayID converted to a CFUUIDRef
      profileInfo  // [kColorSyncDeviceDefaultProfileID: profileURL]
    )
    ```
    Note: get the display UUID with `CGDisplayCreateUUIDFromDisplayID`.
  - Verification: after switching profiles, the display's colors change visibly

- [x] Implement the color profile UI (`FreeDisplay/Views/ColorProfileView.swift`)
  - Implementation hints:
    An expandable "Color Profile" section.
    At the top, show the current profile (e.g. "Color LCD") with a blue icon.
    Below it, a categorized list:
    1. Profiles specific to the current display
    2. A "Generic RGB Profiles" group (blue label with white text)
    3. The list of every system profile (AAA, ACES CG Linear, Adobe RGB, Apple RGB...)
    Each row: a circle icon on the left (⊙/⊕) + the profile name.
    Click to switch.
    Modeled on the color profile area layout in the BetterDisplay screenshots.
  - Verification: the profile list shows completely, and clicking switches the profile

- [x] Implement the color mode UI (`FreeDisplay/Views/ColorModeView.swift`)
  - Implementation hints:
    An expandable "Color Mode" section.
    Show the current mode info (e.g. "Internal (8-bit)") + tags (SDR/RGB/Full Range).
    List the available options:
    - Uniformity Calibration
    - GPU Dithering
    Framebuffer type choices:
    - Standard framebuffer, inverted framebuffer, grayscale framebuffer, inverted grayscale framebuffer
    Get the current color info with `CGDisplayCopyDisplayMode`.
    Get the framebuffer type with `CGDisplayModeCopyPixelEncoding`.
    Modeled on the color mode area in the BetterDisplay screenshots.
  - Verification: the color mode info shows correctly

## Phase acceptance

- The ICC profile list is complete (includes every profile in the screenshots)
- Profile switching works correctly, and the colors actually change
- Color mode info is displayed correctly
- The UI layout matches the BetterDisplay screenshots

**When done**: running project-optimize to reflect is recommended
