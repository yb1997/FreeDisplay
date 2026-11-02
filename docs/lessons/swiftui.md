# Lessons Learned — SwiftUI / UI

> Updated: 2026-03-05

## SwiftUI / MenuBarExtra

- MenuBarExtra needs `.menuBarExtraStyle(.window)` to show custom SwiftUI views (the default menu style only supports Button/Toggle)
- Hiding the Dock icon: set `INFOPLIST_KEY_LSUIElement: true` in project.yml; no need to set it manually in AppDelegate

## UI animation / SwiftUI (Phase 12)

- `withAnimation(.easeInOut(duration: 0.2)) { state.toggle() }` is the simplest way to trigger an expand/collapse animation; there's no need to apply `.animation(_, value:)` to the whole container
- `.transition(.opacity.combined(with: .move(edge: .top)))` gives expanded content its enter/exit effect, so it looks like it slides out from under the button
- The shared icon helper `MenuItemIcon` (defined in MenuBarView.swift) can be used directly by every View in the same module without any extra declaration
- Semantic colors in SwiftUI (green = protection/safety, red = streaming, orange = brightness, gray = settings, purple = color management) communicate each feature's meaning effectively without extra text

## DDC performance cache (Phase 12)

- DDC I2C reads take 50 ms+, so repeated reads triggered by the UI noticeably hurt the experience → solved with an `NSLock` + dictionary cache + 5-second TTL; invalidate the matching cache entry right after a write
- The cache key is a two-level dictionary `[CGDirectDisplayID: [UInt8: VCPCacheEntry]]`, so entries can be invalidated precisely per display and VCP code
- `NSLock.lock()` / `unlock()` must be paired; `defer { lock.unlock() }` is recommended, and note that defer runs correctly on an early return

## SwiftUI performance

- Changing an `@Published` property redraws every View observing that ObservableObject → split the state across several small ObservableObjects, or localize it with `@State`
- Don't put synchronous IOKit/CG calls (such as `CGDisplayCopyColorSpace`) in a View's `body` → fetch them asynchronously with `@State` + `onAppear`/`task {}`
- The `isSwitching = true; syncCall(); isSwitching = false` pattern doesn't work: SwiftUI doesn't render in the middle of synchronous code → you must use async/await to give SwiftUI a chance to redraw
- Wrapping a shared singleton (`XXX.shared`) in `@StateObject` is an anti-pattern: every View rebuild may create a new subscription → use `@ObservedObject` for shared singletons
- The gamma table outlives the View that set it → restore it through GammaService (single writer). Don't write gamma in `onDisappear` (it can fire when the menu closes and would wipe dimming/profile); GammaService restores touched displays when the app quits

## Localization / String Catalog

- The UI source language is English (`developmentLanguage: en`), and the Chinese text lives in the zh-Hans entries of `Localizable.xcstrings`; ❌ don't write Chinese UI text directly in code
- **Literals** passed to `Text("literal")` / `Button` / `Label` / `.help("literal")` / `.alert` / `TextField` are treated as `LocalizedStringKey` and localized automatically
- ⚠️ In these cases the value is a `String` and is **not** localized automatically, so you must write `String(localized: "…")`: ternary expressions `Text(a ? "x" : "y")`, `String` parameters passed to custom components (`ExpandableRow(label:)`, `SectionBadge(title:)`, etc.), error text returned from Services/Models, and `@State` default values
- Key format for interpolation: `String` → `%@`, `Int` → `%lld` (e.g. `"Show All %lld"`); after adding text, add the zh-Hans translation to `Localizable.xcstrings`, or it shows in English on a Chinese system
- Checking for missing translations: after a Release build, read the keys from `Objects-normal/arm64/*.stringsdata` and compare them with the catalog

### L-032: MenuBarExtra(.window) content `.task` doesn't run at launch
- **Symptom**: wake handlers wired in the menu content's `.task`, and singletons first touched by a View (AutoBrightnessService), did nothing until the menu was opened
- **Solution**: register app-wide observers in DisplayManager or AppDelegate, and touch background singletons in `applicationDidFinishLaunching`
- **Lesson**: menu content is built lazily; never put startup work in it
- **Date**: 2026-11-02


### L-039: `@Published` fires on unchanged values; DDC writes need coalescing
- **Symptom**: with the menu open, the 1 s built-in brightness poll re-rendered every view observing the `DisplayInfo` even when the level hadn't changed. On a slow DDC monitor, slider drags queued writes that kept landing after the drag ended.
- **Solution**: only assign `DisplayInfo` properties that actually changed (polls and reconfiguration callbacks). `DDCService.writeAsync` keeps one pending value per display + VCP code, so a queued write always sends the newest value and drops the ones in between.
- **Lesson**: a time throttle limits how often writes start, not how many pile up; coalesce to the latest value instead. `DisplayMode.currentMode(for:)` is now a single `CGDisplayCopyDisplayMode` call; don't enumerate every mode just to describe the current one.
- **Follow-up**: DDCService now runs one serial queue per display. IOAVService enumeration test-reads *every* external display, so it runs as a `busQueue` barrier, and each I2C transaction (a read's request + 40 ms wait + reply included) runs as a plain `busQueue.sync`. Never call `findAVService` inside a `busQueue` block (deadlock). If concurrent IOAVService I/O on two monitors misbehaves, make `queue(for:)` return one shared queue to go back to the old behavior. Slider drags save brightness only at drag end (`setBrightness(persist: false)`).
- **Date**: 2026-11-03
