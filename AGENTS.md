# AGENTS.md — FreeDisplay Project Harness Configuration

> This file defines the harness rules for AI agents working on this project.
> AI agents MUST read this file before making any changes.
> For deeper context, read CLAUDE.md first.

## Project Overview

- **Name**: FreeDisplay
- **Language**: Swift 6.0 (concurrency checking set to minimal)
- **Framework**: SwiftUI (MenuBarExtra) + AppKit
- **Package Manager**: None (zero third-party dependencies, system frameworks only)
- **Build Tool**: XcodeGen (`project.yml`) + xcodebuild
- **Minimum OS**: macOS 14.0
- **Architecture**: MVVM — View → ViewModel → Service

## Architecture Rules

### Layer Separation

```
Views/          → UI display; reads only the ViewModel, or the Service directly (simple cases)
ViewModels/     → State management; bridges Views and Services
Services/       → Business logic; talks to system frameworks (IOKit/CoreGraphics/DDC)
Models/         → Plain data structures (DisplayInfo, DisplayMode, DisplayPreset)
```

- The View layer must not call CoreGraphics / IOKit / CGSet* APIs directly
- Writes to the gamma table must go through GammaService and must not bypass it
- BrightnessService (software brightness) writes through GammaService and doesn't call CGSetDisplayTransferByTable directly

### Module Boundaries

| Directory | Responsibility |
|------|------|
| `FreeDisplay/Services/` | All system-level operations (DDC, brightness, resolution, HiDPI, arrangement, etc.) |
| `FreeDisplay/Views/` | SwiftUI views; file name format: `XxxView.swift` or `XxxRow.swift` |
| `FreeDisplay/ViewModels/` | State management, 1:1 with a View or shared across Views |
| `FreeDisplay/Models/` | Data structures with no side effects |
| `FreeDisplay/Utilities/` | General-purpose utility functions |
| `FreeDisplay/Resources/` | Static resources |
| `docs/` | Project documentation (don't change its structure) |
| `scripts/` | Build and release scripts |

### Protected Files

State the reason explicitly before changing any of these files:

- `FreeDisplay/FreeDisplay.entitlements` — permission declarations; changes affect signing and App Sandbox
- `project.yml` — XcodeGen configuration; after changing it you must rerun `xcodegen generate`
- `ExportOptions.plist` — release signing configuration
- `docs/roadmap/` — planning documents; only update the `[x]` progress markers, don't change the structure

## Coding Standards

### Style Guide

- Swift 6.0 syntax; don't downgrade to backward-compatible patterns
- Prefer SwiftUI views; use AppKit only when necessary
- Private frameworks (CoreDisplay, etc.) must be loaded at runtime with `dlopen` + `dlsym`; `@_silgen_name` is forbidden

### Naming Conventions

- Service classes: `XxxService.swift`, singletons use `static let shared`
- View files: `XxxView.swift`
- Reusable row components: `XxxRow` (a struct, supports `@State`)
- UserDefaults keys: must have the `fd.` prefix (e.g. `fd.launchAtLogin`)
- Bare keys (e.g. `"launchAtLogin"`) are forbidden

### SwiftUI Component Rules

- Row components that need local state (`isHovered`, `isLoading`) → must be a standalone `struct`
- Don't use a `@ViewBuilder` function to host a component that has `@State`

### Concurrency Rules

- Swift 6 concurrency errors → prefer `@MainActor` or `@unchecked Sendable`
- Long-lived C callbacks (e.g. CGDisplayRegisterReconfigurationCallback) → use `Unmanaged.passRetained(self)` and `release()` on unregister
- `passUnretained` is forbidden (risk of dangling pointers)
- Only make genuinely slow operations async (file system scans, network requests); keep microsecond-scale IOKit calls synchronous

## Testing Requirements

### Verification Commands

```bash
# Build check (Debug) — run after every change
cd ~/Desktop/FreeDisplay && xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -20

# Linked-change check (when you changed an interface/model)
grep -r "DisplayInfo\|DisplayManager\|DDCService" FreeDisplay/ --include="*.swift" | grep -v "^Binary"

# Regenerate the xcodeproj (required when project.yml changed)
cd ~/Desktop/FreeDisplay && xcodegen generate

# Release build + package the DMG
cd ~/Desktop/FreeDisplay && ./build.sh
```

### Test Coverage

- This project has no automated test suite (heavily hardware-dependent; testing is mostly manual)
- New DDC features must be verified manually on a real external display
- New HiDPI features must be verified by reconnecting the display

## Git Discipline

### Branch Naming

- `feature/xxx` — new features
- `fix/xxx` — bug fixes
- `refactor/xxx` — refactoring
- `phase-N/xxx` — changes for a ROADMAP phase

### Commit Message Format

Follow Conventional Commits:

```
feat: add automatic brightness adjustment
fix: fix the HiDPI plist write permission issue
refactor: extract GammaService to manage the transfer function in one place
```

### Co-Author Line

```
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Forbidden Operations

- Do NOT: call `CGSetDisplayTransferByTable` / `CGSetDisplayTransferByFormula` directly (bypassing GammaService)
- Do NOT: call `CGDisplayRestoreColorSyncSettings()` (global reset) — use `GammaService.resetAdjustment(for:)`
- Do NOT: implement HiDPI with `CGConfigureDisplayMirrorOfDisplay` (on Apple Silicon it triggers hardware mirroring + mouse stutter)
- Do NOT: reference private framework symbols with `@_silgen_name` (undefined symbol at link time)
- Do NOT: match IOKit services with `CGDisplayVendorNumber/ModelNumber` (unreliable for some displays)
- Do NOT: set `DisplayProductName` in the plist (it overrides the system display name)
- Do NOT: change the directory structure of `docs/roadmap/`
- Do NOT: add third-party dependencies (project policy: zero dependencies)
- Do NOT: access low-level system framework APIs directly from the View layer

## Agent-Specific Notes

### Start-of-work checklist

1. Read `docs/BLOCKING.md` first; resolve any P0/P1 first
2. Read `docs/roadmap/CLAUDE.md` to learn the current phase
3. Read `docs/codemap/CLAUDE.md` → `docs/codemap/file-tree.md` to locate the relevant files

### Linked-change checks after a change

- Changed a `DisplayInfo` property → grep every reference and update them all
- Changed `project.yml` → you must run `xcodegen generate`
- Added a Service/View file → update `docs/codemap/file-tree.md`
- Phase task complete → mark `[x]` in both `docs/roadmap/phase-N.md` and `docs/ROADMAP.md`
- Hit a pitfall → write it in `docs/lessons/{topic}.md` and update the index
- Sleep/wake-related changes → confirm the Service responds to `NSWorkspace.didWakeNotification`

### When to stop and ask the user

- A new private API (CoreDisplay, etc.) is needed
- SIP must be disabled or special system permissions are needed
- The architecture direction changes (MVVM to some other pattern)

### Core framework quick reference

| Framework | Purpose |
|------|------|
| CoreGraphics | Display enumeration, resolution, arrangement |
| IOKit | DDC/CI I2C communication, brightness/contrast |
| ColorSync | ICC profile management |
| CGVirtualDisplay (private) | Virtual displays; vendorID must be non-zero, call on the main thread |
| DisplayServices (dlsym) | Reading/setting built-in display brightness |

<!-- Generated by Harness Engineering system on 2026-03-12. Review and customize. -->
