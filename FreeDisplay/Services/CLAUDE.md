# Services — Business Logic Layer

> The layer that talks to system frameworks, with no UI. Every Service is an `@MainActor` singleton (`static let shared`).

## Responsibilities

Interact directly with macOS system frameworks (IOKit, CoreGraphics, ScreenCaptureKit, ColorSync)
and provide high-level APIs to Views/ViewModels.

## Key patterns

- **Singleton + @MainActor**: every Service is declared `@MainActor final class: ObservableObject, @unchecked Sendable`
- **DDC communication**: DDCService is the low-level dependency of every external display feature; Apple Silicon uses IOAVService
- **Gamma table has a single writer**: GammaService owns writes to CGSetDisplayTransfer*
  - BrightnessService's software brightness is written indirectly through GammaService
  - ❌ No Service/View may call CGSetDisplayTransferByFormula/Table directly
- **CGHelpers.runWithTimeout**: blocking CG calls (apply settings, enableMirror) must be wrapped in it

## File list

| File | Purpose |
|------|------|
| DDCService.swift | Low-level IOKit I2C / IOAVService DDC communication; one serial queue per display, `busQueue` barrier around IOAVService enumeration, writes coalesced to the newest value |
| DisplayManager.swift | Display enumeration, refresh, cross-Service coordination |
| BrightnessService.swift | Software brightness (written through GammaService) |
| GammaService.swift | The single writer of the gamma table |
| AutoBrightnessService.swift | Syncs external displays to the built-in display's brightness (DisplayServices API) |
| ResolutionService.swift | Resolution/HiDPI mode switching |
| ArrangementService.swift | Display arrangement |
| HiDPIService.swift | HiDPI detection and management |
| VirtualDisplayService.swift | CGVirtualDisplay creation/destruction |
| ColorProfileService.swift | ColorSync ICC profiles |
| NotchOverlayManager.swift | Notch overlay |
| SettingsService.swift | UserDefaults persistence |
| UpdateService.swift | App update checking |
| UpdateInstaller.swift | Downloads, verifies (designated requirement + newer version) and installs updates, then relaunches |
| LaunchService.swift | Launch at login |
| CGHelpers.swift | Timeout wrapper for blocking CG calls |

## Cross-Service rules

- **Sleep/wake reapply order**: BrightnessService → GammaService (Brightness supplies data to Gamma)
  - DisplayManager listens for `NSWorkspace.didWakeNotification` → calls reapply (not the menu's `.task`, which only runs once the menu is opened)
- **C callbacks**: use `Unmanaged.passRetained(self)` paired with `release()`; ❌ don't use passUnretained
- **VirtualDisplayService**: HiDPI configuration is runtime-only (❌ don't store autoCreate in UserDefaults);
  `CGVirtualDisplay(descriptor:)` init must run on the main thread

## Testing notes

- DDC/IOKit features must be tested manually on a real external display
- After creating a virtual display, VirtualDisplayService must verify that `CGVirtualDisplay` is non-nil (vendorID must be non-zero)
