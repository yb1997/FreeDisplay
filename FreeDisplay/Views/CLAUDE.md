# Views — SwiftUI View Layer

> Display and interaction only. ❌ Don't write business logic in Views, and don't call Services directly.

## Structure

- **MenuBarView.swift** — the main menu bar view, the entry-point container for every feature
- **DisplayDetailView.swift** — the per-display expanded panel, a container of collapsible sections
- Each section has its own View file (BrightnessSliderView, ColorProfileView, etc.)

## File list

| File | Purpose |
|------|------|
| MenuBarView.swift | Main menu bar view + entry points for every section |
| DisplayDetailView.swift | Display expanded panel (12 sections) |
| BrightnessSliderView.swift | Brightness/contrast slider |
| DisplayModeListView.swift | Resolution mode list (favorites pinned to the top) |
| ArrangementView.swift | Display arrangement (distinct thumbnails for built-in and external displays) |
| ColorProfileView.swift | ICC profile selection |
| ImageAdjustmentView.swift | Image adjustments (gamma/contrast) |
| VirtualDisplayView.swift | HiDPI virtual displays |
| NotchView.swift | Notch overlay |
| MainDisplayView.swift | Main display setting |
| AutoBrightnessView.swift | Ambient-light auto brightness |

## Key patterns

- `@EnvironmentObject var displayManager: DisplayManager` — injected globally
- `@ObservedObject` for shared singletons (❌ don't wrap `.shared` in @StateObject)
- Row components that need hover/loading state → extract into a standalone `struct` (❌ don't use a @ViewBuilder function)
- Component naming: reusable rows are `XxxRow` or `XxxRowView`
- Consistent hover effect: `.background(isHovered ? Color.primary.opacity(0.07) : .clear)`

## Change checklist

- Added a section → change DisplayDetailView.swift + check the MenuBarView layout
- Added a tool entry point → change the tools area of MenuBarView.swift
- Added a row component → it must be a standalone struct, not a @ViewBuilder function
