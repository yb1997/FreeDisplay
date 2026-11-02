# FreeDisplay — Claude Context Entry Point

> Version: 2026-03-05 | Status: Phase 22 complete

## What this project is

A free, open-source alternative to BetterDisplay. A macOS menu bar app for managing displays: DDC brightness/contrast control, resolution/HiDPI management, display arrangement, color management, and virtual displays.
Tech stack: Swift 6 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics, zero third-party dependencies.

## Quick navigation (load on demand)

| What you need to do | File to read |
|-----------|-----------|
| **Check blocking issues before starting work** | `docs/BLOCKING.md` |
| Understand the code structure, find files | `docs/codemap/CLAUDE.md` (index) → `docs/codemap/file-tree.md` (file tree) → `docs/codemap/relationships.md` (relationship diagram) |
| See the project plan and current progress | `docs/roadmap/CLAUDE.md` (overview) → `docs/roadmap/phase-N.md` (details) |
| See working habits/preferences | `docs/habits.md` |
| See pitfalls and lessons learned | `docs/lessons/CLAUDE.md` (index) → `docs/lessons/{topic}.md` (details) |

## Current focus

- **Current phase**: Phase 22 complete. Feature trimming (removed rotation/streaming/PiP/mirroring/configuration protection, etc.) + auto-brightness rewrite + HiDPI plist override implementation.
- **Do not touch**: Don't change the structure of `docs/roadmap/` (planner output); only update the `[x]` progress markers
- **Recent changes**: Phase 21 feature trimming (deleted 15+ files), Phase 22 auto-brightness rewrite (CoreDisplay dlsym), HiDPI switched from the mirroring approach to plist override, arrangement center-alignment fix, HiDPI presets

## Autonomous decision rules

> **Blockers first (the first thing to do when starting work):**
- At every start → read `docs/BLOCKING.md` first → resolve any P0/P1 first → only work on the ROADMAP once everything is cleared
- When you hit a problem you can't solve → add it to `docs/BLOCKING.md`

> **Linked-change rules:**
- Changed a `DisplayInfo` property → grep every reference and update them all
- Changed `project.yml` → you must run `xcodegen generate` to regenerate the xcodeproj
- Added a Service/View file → update `docs/codemap/file-tree.md`

> **Fixes/development:**
- Build fails → fix it until it passes, don't skip it
- Swift 6 concurrency errors → use `@MainActor` or `@unchecked Sendable` (the project sets `SWIFT_STRICT_CONCURRENCY: minimal`)
- New files don't require changes to project.yml (xcodegen automatically includes every source file under FreeDisplay/)

> **SwiftUI component rules:**
- Row components that need local state (isHovered, isLoading) → must be a standalone `struct`, ❌ not a `@ViewBuilder` function (@ViewBuilder functions don't support @State)
- Name reusable row components consistently as `XxxRow` (e.g. DetailRow, ExpandableRow, ProtectionRowView)

> **UserDefaults key naming convention:**
- Every UserDefaults key must have the `fd.` prefix (e.g. `fd.launchAtLogin`, `fd.AutoBrightnessEnabled`)
- ❌ Bare keys (e.g. `"launchAtLogin"`) can collide with system or third-party keys

> **Coordination principle for Services writing shared resources:**
- Two Services must not each independently write the same CoreGraphics resource (e.g. the gamma table) → designate one Service as the owner responsible for the final write
- BrightnessService (software brightness) writes the transfer function through GammaService, not directly with CGSetDisplayTransferByTable
- ❌ The View layer calling `CGSetDisplayTransferByFormula/Table` directly (bypassing GammaService) → ✅ go through `GammaService.apply()`, `pause(for:)` or `resetAdjustment(for:)` instead
- ❌ `CGDisplayRestoreColorSyncSettings()` (global) → ✅ `GammaService.resetAdjustment(for:)` resets only a single display; with nothing active, GammaService restores the display's profile curve by re-assigning its profile (keeps calibration), never a flat identity table
- ❌ Writing gamma from `onDisappear` (it can fire when the menu closes) → only save/clear state there

> **Sleep/wake handling (required):**
- Services that write display hardware state (gamma, software brightness) must respond to `NSWorkspace.didWakeNotification` and reapply
- Already registered: DisplayManager listens for wake → BrightnessService.reapplySoftwareBrightnessIfNeeded + GammaService.reapplyIfNeeded + ResolutionService.reapplySavedModeIfNeeded (and for willSleep, to pause resolution tracking)
- Persist per-display settings by `DisplayInfo.uuid(for:)` / `displayUUID`, never by CGDirectDisplayID (IDs change between sessions)

> **Unmanaged rules for C callbacks:**
- Long-lived C callbacks (CGDisplayRegisterReconfigurationCallback, etc.) → must use `Unmanaged.passRetained(self)` and `release()` on unregister
- ❌ `passUnretained` (risk of dangling pointers)

> **IOKit display matching:**
- Don't use CGDisplayVendorNumber/ModelNumber to match IOKit services (unreliable for some displays)
- Use `NSScreen.localizedName` for display names
- Look up IOKit services by enumerating IODisplayConnect with IOServiceGetMatchingServices (❌ CGDisplayIOServicePort is deprecated)
- DDC external brightness control isn't always available → the UI must degrade gracefully (tell the user when detection fails)

> **Async principles:**
- Only make genuinely slow operations async (file system scans, network requests)
- Keep microsecond-scale IOKit calls (name lookup, property reads) synchronous; they aren't worth making async

> **CGVirtualDisplay private API (must follow):**
- `vendorID` must be non-zero (e.g. `0xEEEE`); when it's 0, `CGVirtualDisplay(descriptor:)` returns nil
- `CGVirtualDisplay(descriptor:)` must be called on the main thread (returns nil on a background thread); `apply(settings)` can run in the background
- Bridging header property names follow Chromium's `virtual_display_mac_util.mm` (`maxPixelsWide`/`maxPixelsHigh`, not `maxPixelSize`)

> **HiDPI implementation (must follow):**
- ❌ `CGConfigureDisplayMirrorOfDisplay` for HiDPI — on Apple Silicon it triggers hardware mirroring mode + mouse stutter
- ✅ Write a plist override to `/Library/Displays/Contents/Resources/Overrides/` — the same approach BetterDisplay uses
- Writing the plist requires administrator privileges → use `NSAppleScript("do shell script ... with administrator privileges")`
- ❌ Setting `DisplayProductName` in the plist — it overrides the system display name
- After enabling, the display must be reconnected to take effect (IOServiceRequestProbe isn't always reliable)

> **Loading private frameworks dynamically:**
- ❌ `@_silgen_name` to reference private framework symbols (undefined symbol at link time)
- ✅ Load at runtime with `dlopen` + `dlsym` (e.g. DisplayServicesGetBrightness)
- ✅ Built-in brightness on Apple Silicon: DisplayServicesGet/SetBrightness (owner-approved 2026-11-02). ❌ CoreDisplay_Display_Get/SetUserBrightness: no-ops there (Get always returns 1.0)

> **Stop and ask the user:**
- When a private API (CoreDisplay, etc.) is needed
- When SIP must be disabled or special system permissions are needed
- When changing the architecture direction (MVVM → something else)

> **Self-maintenance rules:**
- Added, deleted, or changed files → update `docs/codemap/file-tree.md`
- Phase task complete → mark `[x]` in `docs/roadmap/phase-N.md` **and also mark `[x]` in `docs/ROADMAP.md`** (autopilot tracks progress through the latter)
- Hit a pitfall → write it in `docs/lessons/{topic}.md` (and update the `docs/lessons/CLAUDE.md` index)
- Discovered a preference/pattern → write it in `docs/habits.md`
- Got stuck → add it to `docs/BLOCKING.md`
- Resolved a BLOCKING issue → move it to the resolved section

## Verification chain (run after every change)

```bash
# 1. Build check
cd ~/Desktop/FreeDisplay && xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5

# 2. Linked-change check (when you changed an interface/model)
grep -r "DisplayInfo\|DisplayManager\|DDCService" FreeDisplay/ --include="*.swift" | grep -v "^Binary"
```

## Common operations playbook

### Add a feature section (the most common operation in Phases 2-12)
1. Create a new Service in `Services/` (e.g. `BrightnessService.swift`)
2. Create the matching View in `Views/` (e.g. `BrightnessSliderView.swift`)
3. If state management is needed, create a ViewModel in `ViewModels/`
4. Embed the new View in `MenuBarView.swift`
5. Add any needed properties to `DisplayInfo.swift`
6. Run the verification chain

### Implement a DDC feature
1. Implement IOKit I2C communication in `DDCService.swift`
2. Look up the VCP code for the new feature in the DDC/CI standard (e.g. 0x10 = brightness)
3. Call `DDCService.shared.read/write` from the Service
4. Run the verification chain + test manually on a real external display

### Fix a bug
1. Determine whether it's a build error or a runtime error
2. Build error → find it in the xcodebuild output
3. Runtime error → check the logs in Console.app or use the Xcode debugger
4. Fix → run the verification chain

## Design resources

- **App icon design**: use [Nano Banana](https://nano-banana.ai/) (an AI image generator powered by Google Gemini) to generate high-quality icons
  - Generates icons, logos, and UI elements from text descriptions
  - After generating, crop/scale with Python PIL into the multi-size PNGs macOS needs (16/32/64/128/256/512/1024)
  - Icon files live in `FreeDisplay/Assets.xcassets/AppIcon.appiconset/`

## Key conventions

- **Language**: Swift 6.0 (minimal concurrency checking)
- **Minimum OS**: macOS 14.0
- **Architecture**: MVVM (View → ViewModel → Service)
- **Build**: `xcodegen generate && xcodebuild -scheme FreeDisplay -configuration Debug build`
- **No sandbox**: the entitlements turn off App Sandbox (required for DDC/IOKit)
- **No third-party dependencies**: everything uses system frameworks

## Core frameworks

| Framework | Purpose | Phase |
|------|------|-------|
| CoreGraphics | Display enumeration, resolution, arrangement | 1-4 |
| IOKit | DDC/CI I2C communication, brightness/contrast | 2 |
| ColorSync | ICC profile management | 5 |
| CoreGraphics (CGVirtualDisplay) | Virtual displays | 10 |
| DisplayServices (dlsym) | Reading/setting built-in display brightness | 22, 2026-11-02 |
