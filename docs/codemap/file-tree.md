# File Tree — FreeDisplay (Annotated)

> The complete annotated directory structure. For a quick reference see [CLAUDE.md](CLAUDE.md); for module relationships see [relationships.md](relationships.md).

---

```
FreeDisplay/
├── docs/                           # Project documentation
│   ├── roadmap/                    # Phase planning documents (planner output; don't change the structure by hand)
│   │   ├── CLAUDE.md               # Roadmap overview and description of the current phase
│   │   ├── phase-0.md              # Phase 0: Basic scaffolding
│   │   ├── phase-1.md              # Phase 1: Display enumeration + menu bar entry point
│   │   ├── phase-2.md              # Phase 2: DDC brightness/contrast control
│   │   ├── phase-3.md              # Phase 3: Resolution switching
│   │   ├── phase-4.md              # Phase 4: Rotation + arrangement
│   │   ├── phase-5.md              # Phase 5: Color management (ICC profiles)
│   │   ├── phase-6.md              # Phase 6: Image adjustments (gamma/software filters)
│   │   ├── phase-7.md              # Phase 7: Advanced display management
│   │   ├── phase-8.md              # Phase 8: Screen mirroring
│   │   ├── phase-9.md              # Phase 9: Screen streaming + picture-in-picture
│   │   ├── phase-10.md             # Phase 10: Virtual displays
│   │   ├── phase-11.md             # Phase 11: Auto brightness + configuration protection
│   │   ├── phase-12.md             # Phase 12: System color picker + video filters + settings
│   │   ├── phase-13.md             # Phase 13: Critical bug fixes
│   │   ├── phase-14.md             # Phase 14: Performance optimization
│   │   ├── phase-15.md             # Phase 15: Other enhancements
│   │   ├── phase-16.md             # Phase 16: HiDPI virtual displays + presets
│   │   └── phase-17.md             # Phase 17: UI/UX polish
│   ├── codemap/                    # Code navigation map (this directory)
│   │   ├── CLAUDE.md               # Quick reference index (module overview, high-risk files, task table)
│   │   ├── file-tree.md            # Complete annotated directory structure (this file)
│   │   └── relationships.md        # Module relationship diagram + internal Service dependencies + data flow
│   ├── BLOCKING.md                 # Blocking issue tracker (read before starting work)
│   ├── bug-report-2026-11-02.md    # Full code review bug report (v1.1.0)
│   ├── habits.md                   # Development preferences and working habits
│   ├── lessons.md                  # Pitfalls and lessons learned
│   └── ROADMAP.md                  # Overall progress tracker (autopilot tracks the [x] markers here)
├── FreeDisplay/                    # Swift source directory (xcodegen automatically includes every .swift file)
│   ├── App/                        # App entry point, SwiftUI App lifecycle
│   │   ├── AppDelegate.swift       # NSApplicationDelegate; ensures the app appears only in the menu bar; changes affect App lifecycle hooks
│   │   └── FreeDisplayApp.swift    # @main entry point; creates DisplayManager and mounts MenuBarView; changes affect the whole App initialization chain
│   ├── Models/                     # Data model layer (plain data, no side effects)
│   │   ├── DisplayInfo.swift       # ⚠️ Core display model with 12+ @Published properties; every View/Service depends on this class, so adding or removing properties requires a global grep to update everything
│   │   ├── DisplayMode.swift       # Value type for a single display mode (resolution + refresh rate + HiDPI flag); changes to the enumeration logic affect resolution switching and the mode list
│   │   └── DisplayPreset.swift     # Display configuration preset models: DisplayPreset (preset) + DisplayPresetEntry (single-display snapshot); Codable, persisted by PresetService
│   ├── Services/                   # Business logic layer, talks directly to system frameworks
│   │   ├── ArrangementService.swift        # Reads and writes display positions via CGDisplayConfiguration; setOrigins moves several displays in one transaction; setAsMainDisplay shifts every display by -target.origin (live CGDisplayBounds); all CG transactions run inside CGHelpers.runWithTimeout
│   │   ├── AutoBrightnessService.swift     # Polls the built-in display brightness (DisplayServices; IOKit fallback) every 2 s and syncs external displays to it × sensitivity; starts at launch from AppDelegate; 30 s cooldown after manual changes
│   │   ├── BrightnessService.swift         # Unified brightness interface: DisplayServices (IOKit fallback on Intel) for the built-in display, DDC VCP 0x10 for external displays with consecutive-failure counting and re-probe on wake, software (gamma) dimming via GammaService.refresh when DDC is unavailable; factors and DDC state per display
│   │   ├── CGHelpers.swift                 # Shared helper for blocking CG calls: CGHelpers.runWithTimeout(seconds:fallback:operation:) runs blocking WindowServer IPC operations on a background thread with timeout protection; used by ArrangementService, ResolutionService, VirtualDisplayService
│   │   ├── ColorProfileService.swift       # ICC profile enumeration (scans 3 system directories) and switching (ColorSync API); changes affect the color profile list and switching
│   │   ├── DDCService.swift                # ⚠️ Core of DDC/CI communication: IOAVService (Apple Silicon) / IOFramebuffer I2C (Intel), VCP read/write with validated replies (opcode, result, echo, checksum, max > 0), 5-second TTL cache, 3 retries; clearAllCaches on wake
│   │   ├── DisplayManager.swift            # ⚠️ Display enumeration (CGGetOnlineDisplayList) + CGDisplay hot-plug callback + arrangeExternalAboveBuiltin() automatic external display positioning; @Published displays is injected globally, so changes affect the whole display list data flow
│   │   ├── GammaService.swift              # The single gamma writer: builds a 256-entry table from the image adjustment (gamma, gain, color temperature, contrast, invert, quantization) × the software brightness factor; with nothing active it restores the profile curve by re-assigning the display's profile; saved adjustments keyed by display UUID
│   │   ├── HiDPIService.swift              # Writes /Library/Displays/...plist to inject HiDPI scaled modes, needs administrator privileges; changes affect HiDPI override generation
│   │   ├── LaunchService.swift             # Manages launch at login with SMAppService (macOS 13+); changes only affect the Launch at Login feature
│   │   ├── NotchOverlayManager.swift       # Creates a black overlay NSWindow (screenSaver level) over the notch area of the built-in display; changes affect the overlay's appearance and window level
│   │   ├── ResolutionService.swift         # Switches display modes via CGConfigureDisplayWithDisplayMode; applyModeSync is async, and the whole CG transaction runs inside CGHelpers.runWithTimeout; resolvedTargetDisplayID() falls back to VirtualDisplayService when mirroring is detected; changes affect the resolution switching success rate
│   │   ├── SettingsService.swift           # Persists global and per-display settings with UserDefaults + JSON files; when changing it, watch the key naming (must have the fd. prefix) and backward compatibility
│   │   ├── UpdateInstaller.swift           # In-app updater: downloads the release DMG, mounts it, checks the new app against the running app's designated requirement (same bundle ID + certificate) and that its own version is newer, swaps it in (admin prompt only if the folder isn't writable), and relaunches via a shell helper; refuses from App Translocation, /Volumes or ad-hoc signed copies
│   │   ├── UpdateService.swift             # Checks GitHub releases/latest (launch: at most hourly; Check for Updates: always), records the version, release page and FreeDisplay.dmg asset URL
│   │   ├── VirtualDisplayService.swift     # Virtual display creation/destruction: CGVirtualDisplay private API (vendorID 0xEEEE, serial derived from the config UUID, created on the main thread), CGHelpers.runWithTimeout timeout protection; start(configID:) turns a saved config on; autoCreate skips configs whose identity is already online
│   │   └── PresetService.swift             # Preset management: save/load/apply display configuration presets; reads the current display state through DisplayManagerAccessor; presets.json is stored in ~/Library/Application Support/FreeDisplay/
│   ├── Utilities/                  # Utility extensions
│   │   └── NSScreenExtension.swift         # NSScreen extension: finds the NSScreen for a CGDirectDisplayID and gets its displayID; NotchView and NotchOverlayManager depend on it
│   ├── Localizable.xcstrings          # String Catalog: source language en (English keys in code), zh-Hans translations; the system language decides the UI language
│   ├── InfoPlist.xcstrings            # zh-Hans translation of the Info.plist text (NSScreenCaptureUsageDescription)
│   ├── FreeDisplay-Bridging-Header.h       # Private API declarations: CGVirtualDisplay (macOS 14+) and IOAVService (Apple Silicon DDC); property names verified against the Chromium source (maxPixelsWide/maxPixelsHigh, not maxPixelSize)
│   └── Views/                      # SwiftUI view layer
│       ├── ArrangementView.swift           # Drag-to-arrange canvas for multiple displays (distinct thumbnails for built-in and external) + set-as-main-display button; depends on ArrangementService
│       ├── AutoBrightnessView.swift        # Auto-brightness toggle + sensitivity slider + ambient light lux readout; depends on AutoBrightnessService
│       ├── BrightnessSliderView.swift      # Per-display brightness slider (200 ms debounce) + global combined brightness control; depends on BrightnessService + DDCService
│       ├── ColorProfileView.swift          # ICC profile list (Recommended/All groups) and switching; depends on ColorProfileService
│       ├── DisplayDetailView.swift         # ⚠️ Per-display expanded panel, a container of collapsible sections (three groups); adding or removing a section always changes this file, and MenuBarView must be kept in sync
│       ├── DisplayModeListView.swift       # Resolution mode list (HiDPI/native/other groups), star to pin favorites, click to switch; depends on ResolutionService
│       ├── ImageAdjustmentView.swift       # 11 image adjustment sliders (contrast/gamma/gain/color temperature/per-channel/quantization/inversion); depends on GammaService
│       ├── MainDisplayView.swift           # "Set as Main Display" row; shows a status label when it's already the main display; depends on ArrangementService
│       ├── MenuBarView.swift               # ⚠️ Main menu bar view: display list + expand/collapse + tools area + settings area + PresetListView; the entry-point container for every feature, so changes affect the global layout
│       ├── NotchView.swift                 # Notch info + overlay toggle (shown only for built-in displays with a notch); depends on NotchOverlayManager
│       ├── HiDPIView.swift                 # HiDPI override status row (plist approach) + write/restore button; depends on HiDPIService
│       ├── VirtualDisplayView.swift        # Virtual display configuration list + creation form (preset resolutions) + one-click HiDPI preset; depends on VirtualDisplayService
│       └── SavePresetView.swift            # Saves the current display state as a preset; inline form (name + icon picker); calls PresetService.captureCurrentState + addPreset
├── FreeDisplay.xcodeproj/          # Xcode project file (generated by xcodegen; don't edit by hand)
├── .gitignore                      # Git ignore rules
├── build.sh                        # Quick build script
├── CLAUDE.md                       # Claude context entry point (project rules, decision conventions)
└── project.yml                     # xcodegen configuration; after changing it you must rerun xcodegen generate
```
