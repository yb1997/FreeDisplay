# Code Map — FreeDisplay (Quick Reference)

> **Purpose**: Quick code navigation reference for Claude. For the detailed file tree see `file-tree.md`; for the module relationship diagram see `relationships.md`.
> **Maintenance**: Update the descriptions and the module relationship diagram after major structural changes.

---

## Key Entry Points

- `CLAUDE.md`
- `docs/codemap/CLAUDE.md` (this file)
- `docs/roadmap/CLAUDE.md`

Details: [file-tree.md](file-tree.md) | [relationships.md](relationships.md)

---

## Module Summary

| Module | Responsibility | Key files | Notes |
|------|------|---------|---------|
| **App** | App lifecycle, MenuBarExtra scene declaration | `FreeDisplayApp.swift` | DisplayManager is created here and injected as an environmentObject |
| **Models** | Plain data structures, ObservableObject | `DisplayInfo.swift`, `DisplayMode.swift` | Changing a DisplayInfo property requires a global grep to update everything |
| **Services** | Talks to system frameworks, no UI | `DDCService.swift`, `DisplayManager.swift`, `BrightnessService.swift`, etc. | Most Services are @MainActor singletons |
| **Views** | SwiftUI views, display and interaction only | `MenuBarView.swift`, `DisplayDetailView.swift` | Don't write business logic in Views; call Services |
| **Utilities** | System type extensions | `NSScreenExtension.swift` | Many places depend on it; don't change it lightly |

---

## High-Risk Files ⚠️

| File | Why it's risky | Required after changing it |
|------|---------|---------|
| `Models/DisplayInfo.swift` | 12+ @Published properties; every View and Service depends on it | grep every reference and update them all |
| `Services/DisplayManager.swift` | @Published displays injected globally, hot-plug callback | Verify hot-plug and multi-display enumeration after changing it |
| `Services/DDCService.swift` | Low-level IOKit I2C communication, the foundation of every external display feature | Must be tested manually on a real external display |
| `Views/MenuBarView.swift` | The entry-point container for every feature, nests every section entry point | After adding a section, check the layout and scroll height |
| `Views/DisplayDetailView.swift` | Expanded container for 12 sections, many state variables | When adding a section, make sure @State names don't collide |

---

## Task Reference Table

| Task | Files to change |
|------|--------------|
| Add a display property (e.g. HDR status) | `Models/DisplayInfo.swift` → grep every reference → related Views/Services |
| Add a DDC VCP feature (e.g. volume control) | `Services/DDCService.swift` (add the VCP constant) → new Service → new View → `Views/DisplayDetailView.swift` (add the section) → `docs/codemap/CLAUDE.md` |
| Add a menu bar tool entry point (not display-related) | `Views/MenuBarView.swift` (add the entry point in the tools area) → new View/Service → `docs/codemap/CLAUDE.md` |
| Change the resolution switching logic | `Services/ResolutionService.swift`, `Models/DisplayMode.swift`; test the impact on `Views/DisplayModeListView.swift` |
| Change brightness reads/writes | `Services/BrightnessService.swift`; for external display sync, check `Services/DDCService.swift` |
| Change image adjustment effects | `Services/GammaService.swift` (table calculation), `Views/ImageAdjustmentView.swift` (UI slider mapping) |
| Add a new persisted setting | `Services/SettingsService.swift` (Keys + @Published property + loadAll/persist) → related View |
| Change notification/hot-plug handling | `Services/DisplayManager.swift` (displayReconfigCallback + refreshDisplays) |
| Change HiDPI override generation | `Services/HiDPIService.swift` (generateScaledModes + plist path) |
| Change virtual display logic | `Services/VirtualDisplayService.swift`, `FreeDisplay-Bridging-Header.h` (private API declarations) |

---

## Pitfalls

- **DisplayInfo property changes**: changed `DisplayInfo` → grep every reference and update them all; otherwise it may build but the logic will be wrong
- **project.yml**: after changing it you must run `xcodegen generate` to regenerate the xcodeproj
- **New source files**: xcodegen automatically includes every `.swift` file under `FreeDisplay/`; no need to change `project.yml`
- **Swift 6 concurrency**: the project sets `SWIFT_STRICT_CONCURRENCY: minimal`; handle concurrency errors with `@MainActor` or `@unchecked Sendable`
- **No sandbox**: the entitlements turn off App Sandbox, so IOKit, /Library/Displays, etc. can be accessed directly
- **Bridging header private APIs**: the CGVirtualDisplay / IOAVService declarations in `FreeDisplay-Bridging-Header.h` were verified against the Chromium source; recheck the property names before changing them
- **HiDPIService permissions**: writing to `/Library/Displays/` needs administrator privileges; without them it returns an error string for the UI to show
- **CGHelpers.runWithTimeout**: WindowServer IPC can block the main thread, so every CG configuration transaction must go through this helper on a background thread with timeout protection
