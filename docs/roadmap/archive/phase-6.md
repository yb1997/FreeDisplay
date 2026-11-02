# Phase 6: Image adjustments ✅

> Core value: software-level color adjustment — contrast, gamma, gain, color temperature, independent RGB channels

## Task list

- [x] Implement the gamma table adjustment engine (`FreeDisplay/Services/GammaService.swift`)
  - Implementation hints:
    macOS implements software-level color adjustment through the gamma table. Core APIs:
    ```swift
    // Get the current gamma table
    CGGetDisplayTransferByTable(displayID, capacity, &redTable, &greenTable, &blueTable, &sampleCount)
    // Set a custom gamma table
    CGSetDisplayTransferByTable(displayID, sampleCount, redTable, greenTable, blueTable)
    // Or use formula mode (more common)
    CGSetDisplayTransferByFormula(displayID,
      redMin, redMax, redGamma,
      greenMin, greenMax, greenGamma,
      blueMin, blueMax, blueGamma)
    ```
    Wrap them in a high-level interface:
    - `setGamma(displayID, value: Double)` — overall gamma (0.1~3.0, default 1.0)
    - `setGain(displayID, value: Double)` — overall gain (mapped to the max parameter)
    - `setColorTemperature(displayID, kelvin: Int)` — color temperature (converted to RGB ratios)
    - `setRGBGamma(displayID, r/g/b: Double)` — independent RGB gamma
    - `setRGBGain(displayID, r/g/b: Double)` — independent RGB gain
    - `resetGamma(displayID)` — reset with `CGDisplayRestoreColorSyncSettings()`
    Color temperature to RGB conversion: use the Planckian locus approximation (Tanner Helland algorithm),
    which takes a color temperature in K and outputs RGB ratio coefficients.
  - Verification: after `setGamma(displayID, 0.5)` the screen gets visibly brighter/darker

- [x] Implement software contrast adjustment (`GammaService` extension)
  - Implementation hints:
    Contrast is implemented by adjusting the min/max range of the gamma table:
    - Increase contrast: widen the max - min gap
    - Decrease contrast: narrow the max - min gap
    Formula: `min = 0.5 - contrast/2`, `max = 0.5 + contrast/2`, with contrast in the range 0~1.
    Note: external displays can also set hardware contrast through DDC VCP 0x12 (Phase 2 already provides the DDC basics).
  - Verification: adjusting contrast visibly changes the picture's contrast

- [x] Implement invert colors (`GammaService` extension)
  - Implementation hints:
    Invert colors = swap min and max in the gamma table:
    `CGSetDisplayTransferByFormula(displayID, 1,0,1, 1,0,1, 1,0,1)` gives a full inversion.
    Or use the accessibility API `CGDisplaySetInvertedPolarity(true)` if it's available.
  - Verification: after turning on inversion, every color on the screen is inverted

- [x] Implement the image adjustment UI (`FreeDisplay/Views/ImageAdjustmentView.swift`)
  - Implementation hints:
    An expandable "Image Adjustments" section, modeled on the BetterDisplay screenshots:
    several slider groups arranged vertically:
    1. Contrast — Slider (⊙ icon) 0%
    2. Gamma — Slider (✦ icon) 0%
    3. Gain — Slider (⚡ icon) 0%
    4. Color temperature — Slider (🔥 icon) 0%
    5. Quantization — Slider (📊 icon) infinite
    ---divider---
    6. Gamma (red) R — Slider 0%
    7. Gamma (green) G — Slider 0%
    8. Gamma (blue) B — Slider 0%
    ---divider---
    9. Gain (red) R — Slider 0%
    10. Gain (green) G — Slider 0%
    11. Gain (blue) B — Slider 0%
    ---
    ⚠️ "Adjustments may affect HDR content!" warning text
    Bottom buttons: Invert Colors / Pause Color Adjustments / Reset Image Adjustments
    Each Slider has an icon and label on the left and shows the percentage value on the right.
  - Verification: the UI matches the BetterDisplay screenshots exactly

- [x] Implement the quantization feature (`GammaService` extension)
  - Implementation hints:
    Quantization = a visual simulation of reduced color bit depth. Implement the stepping by modifying the gamma table:
    map the 256 gray levels to N levels (N = the quantization level), producing a banding effect.
    "Infinite" = no quantization (the original 256 levels).
  - Verification: with quantization set to a low value, visible banding appears in the picture

## Phase acceptance

- All 11 sliders work correctly
- Gamma/gain/color temperature adjustments actually change the screen's colors
- Independent RGB channel adjustment works
- The Invert Colors/Pause/Reset buttons work
- The UI matches the BetterDisplay image adjustment screenshots

**When done**: running project-optimize to reflect is recommended
