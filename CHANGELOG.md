# Changelog

All notable changes to FreeDisplay are documented here.

---

## v1.2.1 (2026-11-02)

### Improvements

- **Check for Updates** in Settings: checks GitHub right away and shows whether you're up to date, offers a **Download** button when a new version is out, and tells you when GitHub can't be reached. The automatic check at launch still runs quietly.

### Notes

- The new texts are English-only for now in the Chinese translation.
- Same install note as v1.1.0: the app isn't notarized; on first launch use **System Settings → Privacy & Security → Open Anyway**.

---

## v1.2.0 (2026-11-02)

Fixes from a full review of the app on Apple Silicon. Details: [docs/bug-report-2026-11-02.md](https://github.com/yb1997/FreeDisplay/blob/main/docs/bug-report-2026-11-02.md).

### Fixes

- **Built-in display brightness works on Apple Silicon**: the slider, the combined slider and fades now change the MacBook screen (they only moved the slider before).
- **Auto Brightness** reads the real built-in brightness (it synced external displays to 100%), starts at launch, and keeps its sensitivity and on/off setting.
- **Brightness is remembered** per display after a relaunch, and the slider follows Auto Brightness and presets.
- **Brightness keys** step evenly when pressed quickly.
- **DDC monitors** aren't switched to software dimming by one failed command (common right after wake or plug-in), are checked again after wake, and aren't dimmed twice. Garbage DDC replies are rejected.
- **Image Adjustments**: Reset, Pause and closing the menu no longer remove your color profile or software dimming; positive Contrast and Gain now have an effect.
- **Resolution** changes made in System Settings are no longer undone after sleep.
- **Set as Main Display** keeps the layout's shape; *Keep external displays above the built-in display* places several monitors side by side.
- **HiDPI** asks before enabling (it needs an administrator password) and remembers a "no" for that monitor.
- **Virtual displays** are no longer blocked from auto-creating by a real monitor of the same size, and each one gets its own identity.
- **Menu** scrolls to Settings, Virtual Displays or Auto Brightness when you expand them.
- **Auto Brightness switch** can always be turned off; the **Current** preset accounts for HiDPI; **Launch at Login** shows its real status.

### Improvements

- Saved virtual displays can be turned on and off without deleting them.

### Notes

- Existing virtual displays get a new identity once, so macOS may forget their position one time.
- A monitor without DDC gets its saved dimming back a few seconds after launch or wake.
- A few new texts are English-only for now in the Chinese translation.
- Same install note as v1.1.0: the app isn't notarized; on first launch use **System Settings → Privacy & Security → Open Anyway**.

---

## v1.1.0 (2026-10-31)

First release of the [yb1997/FreeDisplay](https://github.com/yb1997/FreeDisplay) fork, built on [huberdf/FreeDisplay](https://github.com/huberdf/FreeDisplay) by MingJie Ji.

### Fixes

- **HiDPI keeps 144Hz**: the built-in *HiDPI Mode* preset now picks the largest HiDPI mode that runs at the display's top refresh rate (e.g. 2304×1296 HiDPI @ 144Hz instead of 2560×1440 HiDPI @ 60Hz), and re-applying a preset fixes a wrong refresh rate.
- **Color Profile** shows the active profile's name instead of "Unknown" on external displays.
- **Recommended color profiles** list the display's own profile plus sRGB and Display P3, instead of the MacBook's "Color LCD" or the cinema DCI-P3 profile.
- **Crash** when pressing the brightness keys on an external display.
- **Menu** no longer collapses to zero height.

### Improvements

- **English UI** with a Simplified Chinese translation (String Catalogs).
- **Brightness key permission banner**: shows when Accessibility access is missing, opens the right settings pane, and picks up the permission without a restart.
- **"Keep external displays above the built-in display"** is now an opt-in toggle instead of being forced on.
- **Stable signing**: releases are signed with a fixed self-signed certificate, so the Accessibility permission survives updates.
- **Update check** now points at this fork's releases.

### Install note

The app is not notarized (no Apple Developer account). On first launch macOS will say it can't verify the developer: open **System Settings → Privacy & Security** and click **Open Anyway**.

---

## v1.0.0 (2026-03-05)

Initial public release — full-featured BetterDisplay alternative.

### Core Features

- **Display Detection & Menu Bar UI** (Phase 1)
  - Multi-monitor detection (built-in + external)
  - MenuBarExtra-based UI with per-display panels
  - Display identification (visual flash)

- **DDC Brightness & Contrast Control** (Phase 2)
  - IOKit I2C DDC/CI communication
  - Hardware brightness and contrast sliders for external monitors
  - Software gamma brightness for built-in displays

- **Resolution Management & HiDPI** (Phase 3)
  - Resolution list with HiDPI/native/scaled modes
  - HiDPI virtual display creation (CGVirtualDisplay)
  - Resolution slider for quick switching

- **Rotation & Arrangement** (Phase 4)
  - Display rotation: 0°/90°/180°/270°
  - Visual display arrangement editor

- **Color Management** (Phase 5)
  - ICC color profile switching per display
  - Color mode display (8-bit/10-bit, SDR/HDR)

- **Image Adjustment** (Phase 6)
  - Software contrast, gamma, color temperature
  - Per-channel RGB gain control
  - Color inversion

- **Advanced Display Management** (Phase 7)
  - Set primary display
  - Display info panel (resolution, refresh rate, vendor)

- **Screen Mirroring** (Phase 8)
  - Mirror any display to any other display
  - Mirror enable/disable toggle

- **Screen Streaming & Picture-in-Picture** (Phase 9)
  - ScreenCaptureKit-based screen capture
  - Floating PiP window with configurable size and position
  - Stream controls: flip, rotate, scale, crop, opacity, video filters

- **Virtual Display** (Phase 10)
  - Create HiDPI virtual/dummy displays
  - Useful for headless Macs or extending workspace

- **Config Protection & Auto Brightness** (Phase 11)
  - Prevent macOS from resetting display configuration
  - Time-based auto brightness scheduling

- **Notch Management** (Phase 12)
  - Notch overlay show/hide for MacBooks with notch

### Stability & Polish

- **Critical Bug Fixes** (Phase 13)
  - DDC communication reliability improvements
  - CoreGraphics API usage corrections

- **Performance Optimization** (Phase 14)
  - Async display enumeration
  - Reduced UI blocking on IOKit calls

- **UX Improvements** (Phase 15)
  - Improved slider responsiveness
  - Better error states and user feedback

- **Comprehensive Bug Fixes — 134 bugs** (Phase 16)
  - 5 rounds of systematic bug fixing across all features
  - 3 rounds of UI/UX polish
  - Unified hover effects across all views
  - Extracted reusable components: DetailRow, ExpandableRow, ProtectionRowView
  - DisplayDetailView three-group layout
  - Rotation 2×2 grid layout
  - ArrangementView interior/exterior display thumbnail distinction
  - DisplayModeList favorites pinned to top
  - ConfigProtection active protection badge

- **DDC / HiDPI / Notch Targeted Fixes** (Phase 17)
  - CGVirtualDisplay: vendorID must be non-zero
  - CGVirtualDisplay must be created on main thread
  - Bridging header property name corrections
  - One-click display presets completed

- **CG Timeout Protection + Wake Recovery** (Phase 18)
  - CoreGraphics call timeout protection
  - Sleep/wake display state recovery
  - GammaService wake notification handler
  - BrightnessService wake reapplication

### Preset System

- **Display Preset One-Click Switching** (Phase 19)
  - Save full display configuration as named preset
  - Instant restore: resolution, brightness, rotation, color profile
  - Preset management UI (create, rename, delete)

### Release

- **App Icon, DMG Packaging, Launch at Login** (Phase 20)
  - App icon: gradient blue-purple monitor with "F" lettermark
  - DMG installer with Applications shortcut
  - SMAppService-based launch at login (macOS 13+)
  - README, CHANGELOG, release automation script
  - UpdateService pointing to GitHub Releases API
