# Module Relationships — FreeDisplay

> Module relationship diagram, internal Service dependencies, and data flow. For a quick reference see [CLAUDE.md](CLAUDE.md); for the file tree see [file-tree.md](file-tree.md).

---

## Module Relationship Diagram

```
App (FreeDisplayApp)
  └── @StateObject DisplayManager
        └── @Published [DisplayInfo]
              └── MenuBarView (@EnvironmentObject DisplayManager)
                    ├── DisplayRowView
                    │     └── DisplayDetailView  ← 12 sections (three groups)
                    │           ├── BrightnessSliderView     → BrightnessService → DDCService
                    │           ├── DisplayModeListView      → ResolutionService
                    │           ├── ColorProfileView         → ColorProfileService
                    │           ├── ImageAdjustmentView      → GammaService
                    │           ├── MainDisplayView          → DisplayManager.setAsMainDisplay → ArrangementService
                    │           ├── NotchView                → NotchOverlayManager
                    │           └── HiDPIVirtualRowView      → VirtualDisplayService
                    ├── ArrangementView          → ArrangementService
                    ├── VirtualDisplayView       → VirtualDisplayService
                    ├── AutoBrightnessView       → AutoBrightnessService → BrightnessService
                    └── SettingsView             → SettingsService, LaunchService
```

---

## Services Internal Dependencies

```
BrightnessService ──────────→ DDCService (DDC brightness read/write for external displays)
AutoBrightnessService ──────→ BrightnessService (called after mapping lux→brightness)
DisplayManager ─────────────→ BrightnessService (initializes brightness asynchronously on refresh)
               ─────────────→ ArrangementService (setAsMainDisplay)
               ─────────────→ arrangeExternalAboveBuiltin() (positions external displays automatically after hot-plug)

CGHelpers (shared helper) ──→ Used by these Services (WindowServer IPC timeout protection):
  ArrangementService (setPosition/setOrigins/setAsMainDisplay CG transactions)
  ResolutionService (applyModeSync CG transaction)
  VirtualDisplayService (CGVirtualDisplay apply transaction)

GammaService (gamma owner) ─→ The only Service that writes CGSetDisplayTransferByTable
  BrightnessService ─────────→ GammaService.refresh() (final table = image adjustment × software brightness factor)
  ❌ The View layer must not call CGSetDisplayTransferByFormula/Table directly
  ❌ Don't use CGDisplayRestoreColorSyncSettings() (global); use GammaService.resetAdjustment(for:) instead

ResolutionService ──────────→ VirtualDisplayService.virtualDisplayID(for:) (fallback when mirroring is detected)
```

---

## Data Flow

```
One-way data flow (reactive):
  CGDisplayAPI / IOKit → Services → DisplayInfo (@Published) → Views (reactive SwiftUI)
  User interaction    → Views   → Services → Hardware

Sleep/wake data flow:
  NSWorkspace.willSleepNotification → DisplayManager → ResolutionService.beginSleepSuppression()
  NSWorkspace.didWakeNotification → DisplayManager.handleWake()
    → BrightnessService.reapplySoftwareBrightnessIfNeeded()
    → GammaService.reapplyIfNeeded()
    → ResolutionService.reapplySavedModeIfNeeded()
    → ResolutionService.endSleepSuppression()

Hot-plug data flow:
  CGDisplayRegisterReconfigurationCallback → DisplayManager.displayReconfigCallback
    → refreshDisplays()
    → arrangeExternalAboveBuiltin()
    → @Published displays updates → every View re-renders

Virtual display data flow (runtime only, not persisted):
  VirtualDisplayView → VirtualDisplayService.enableHiDPIVirtual()
    → CGVirtualDisplay(descriptor:) [main thread, vendorID=0xEEEE, serial from config UUID]
```
