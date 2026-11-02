# Models — Data Model Layer

> Plain data structures, ObservableObject.

## Files

| File | Purpose |
|------|------|
| DisplayInfo.swift | State model for a single display (high risk) |
| DisplayMode.swift | Display mode value type (resolution + refresh rate + HiDPI) |

---

## DisplayInfo.swift — High risk

The core display model, with many `@Published` properties. **Every View and Service depends on this class.**

### Change protocol

1. Added or removed an `@Published` property → `grep -r "DisplayInfo" FreeDisplay/ --include="*.swift"` to find every reference
2. Update every reference to match (a passing build ≠ correct logic)
3. `loadDetails()` is an async method, called for new displays in `DisplayManager.refreshDisplays()`

### Key properties

- `displayID: CGDirectDisplayID` — hardware identifier; may change after hot-plug (can't be used as a persistent key)
- `isBuiltin` — determined with `CGDisplayIsBuiltin()`
- `bounds` — from `CGDisplayBounds()`; must be refreshed after hot-plug or arrangement changes
- `name` — from `NSScreen.localizedName` (more reliable than the IOKit vendorID)
- The `rotation` property was removed in Phase 21 (deleted together with RotationService/RotationView)

---

## DisplayMode.swift

Value type for a single display mode (resolution + refresh rate + HiDPI flag).

- The static method `currentMode(for:)` gets the current mode
- `availableModes(for:)` gets the list of available modes (including HiDPI variants)
- Changes affect ResolutionService and DisplayModeListView

### HiDPI notes

- HiDPI modes are distinguished by the `kIOScalingModeKey` flag, not simply by 2× resolution
- HiDPI modes for virtual displays are injected dynamically by VirtualDisplayService, not taken from DisplayMode
