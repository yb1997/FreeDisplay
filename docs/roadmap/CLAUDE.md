# Roadmap — FreeDisplay

> Created: 2026-03-02 | Goal: a free macOS display management menu bar app that fully replaces BetterDisplay

## Background and motivation

BetterDisplay is the most full-featured display management tool on macOS, but it's expensive. This project aims to build a free, open-source alternative with feature parity, covering every core feature: DDC control, HiDPI management, screen streaming/picture-in-picture, virtual displays, and more.

## Requirements summary

### Feature area 1: Basic display management
- Multi-display detection and list (built-in + external)
- Brightness slider control (DDC protocol for external displays, system API for the built-in display)
- Resolution switching (including the HiDPI mode list, native + scaled modes)
- Set as main display
- Screen rotation (90°/180°/270°)
- Display arrangement (visual drag and drop)

### Feature area 2: Full DDC/CI control
- Read and set brightness, contrast, and volume
- Input source switching
- Read all VCP parameters from the device and update them

### Feature area 3: Color and image
- Color mode switching (8-bit/10-bit, SDR/HDR, framebuffer type)
- ICC color profile switching
- Image adjustments (contrast, gamma, gain, color temperature, independent RGB channel adjustment)
- Invert colors

### Feature area 4: Screen mirroring and streaming
- Screen mirroring (choose source → target)
- Screen streaming (with flip/rotate/scale/underscan/opacity/crop/video filters)
- Picture-in-picture (floating window, with window level, lock, click-through, shadow, and other options)

### Feature area 5: Advanced features
- Virtual display/dummy display creation and management
- Configuration protection (prevents the system from resetting resolution/refresh rate/color and other settings)
- Auto brightness
- Display notch management
- Prevent sleep while connected

## Technical approach summary

- **Tech stack**: Swift 6.2 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics + ScreenCaptureKit + ColorSync
- **Architecture**: macOS menu bar app (MenuBarExtra), MVVM architecture, project managed by xcodegen
- **Minimum OS**: macOS 14.0 (CGVirtualDisplay needs macOS 14+)
- **Key constraints**: needs Accessibility permission (DDC), Screen Recording permission (streaming), App Sandbox turned off

### Core design decisions

| Decision | Choice | Reason |
|------|------|------|
| UI framework | SwiftUI MenuBarExtra | Native support on macOS 13+, lightweight, no Dock icon |
| Project management | xcodegen + project.yml | CLI-friendly, avoids managing the .xcodeproj by hand |
| DDC communication | Direct IOKit I2C communication | No third-party libraries, based on MonitorControl's open-source implementation |
| Screen capture | ScreenCaptureKit | Official Apple API, macOS 12.3+, replaces the deprecated CGDisplayStream |
| Virtual displays | CGVirtualDisplay | Official API on macOS 14+, more stable than the old IOKit approach |
| Color management | ColorSync + CoreGraphics | Native system ICC management |
| Architecture | MVVM | SwiftUI best practice, View-ViewModel-Service layering |

## Phase overview

| Phase | Name | Status | Details |
|-------|------|------|------|
| 0-17 | Archived | ✅ | [archive/](archive/) |
| 18 | Stability hardening | ✅ | [phase-18.md](phase-18.md) |
| 19 | Display preset system | ✅ | [phase-19.md](phase-19.md) |
| 20 | Release preparation | ✅ | [phase-20.md](phase-20.md) |
| 21 | Feature trimming | ✅ | [phase-21.md](phase-21.md) |
| 22 | Auto-brightness rewrite | ✅ | [phase-22.md](phase-22.md) |

## Decision log

| Date | Decision | Alternatives | Rationale |
|------|------|---------|------|
| 2026-03-02 | Use xcodegen instead of a hand-managed Xcode project | SPM executable, hand-managed xcodeproj | CLI-friendly, git-manageable, generates the xcodeproj automatically |
| 2026-03-02 | MenuBarExtra instead of NSStatusItem | NSStatusItem + NSPopover | Native SwiftUI, simpler code, supported on macOS 13+ |
| 2026-03-02 | Minimum macOS 14 | macOS 12/13 | CGVirtualDisplay needs 14+, and the user is currently on macOS 15 |
| 2026-03-02 | No third-party dependencies | MonitorControl/Lunar libraries | Fully self-controlled, and a way to learn the low-level APIs |
| 2026-03-04 | Plan Phases 18-20 | Keep fixing bugs | The features are complete; focus on stability → preset system → release distribution |

## Requirements confirmation log

| Date | Item confirmed | Details |
|------|--------|------|
| 2026-03-02 | Feature scope | User confirmed: wants every feature, including streaming/PiP/virtual displays |
| 2026-03-02 | Project location | ~/Desktop/FreeDisplay |
| 2026-03-02 | Development environment | Xcode installed, xcodegen 2.44.1 installed |
| 2026-03-02 | User hardware | MacBook built-in display + HKC H2435Q 2K external display |
| 2026-03-04 | HiDPI debugging experience | Constraints such as a non-zero CGVirtualDisplay vendorID, creation on the main thread, and runtime-only HiDPI configuration have been recorded in lessons |
