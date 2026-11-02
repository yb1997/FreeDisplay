# Phase 12: Wrap-up and release ✅

> Core value: settings persistence, UI polish, performance optimization, and a distributable .app

## Task list

- [x] Implement global settings persistence (`FreeDisplay/Services/SettingsService.swift`)
  - Implementation hints:
    Persist every setting with `UserDefaults.standard` + `@AppStorage`:
    - Each display's brightness/contrast/gamma preferences
    - Resolution selection preferences
    - Configuration protection options
    - Virtual display configurations
    - Auto brightness settings
    - Stream/PiP window position and size
    - Favorite resolution modes
    Store complex configurations (virtual displays, snapshots) as JSON files in
    `~/Library/Application Support/FreeDisplay/`.
  - Verification: change a setting → quit → relaunch → the setting is restored

- [x] Implement launch at login (`FreeDisplay/Services/LaunchService.swift`)
  - Implementation hints:
    Register a login item with `SMAppService.mainApp.register()` (macOS 13+).
    Or use the `LaunchAtLogin` library.
    Add a "Launch at Login" Toggle to the settings.
  - Verification: after restarting the Mac, FreeDisplay launches automatically

- [x] Implement the "Video Filter Window" tool (`FreeDisplay/Views/VideoFilterWindow.swift`)
  - Implementation hints:
    Add an entry point to the "Tools" area (like "Video Filter Window" in the screenshots).
    Create a standalone window that previews CIFilter effects in real time.
    Available filters: grayscale, invert, blur, sharpen, hue rotation, gamma adjustment.
    The chosen filter is applied to the stream/PiP image.
  - Verification: the filter window shows correctly, and choosing a filter changes the streamed image

- [x] Implement the "System Colors" tool (`FreeDisplay/Views/SystemColorView.swift`)
  - Implementation hints:
    Add an entry point to the "Tools" area (like "System Colors" in the screenshots).
    Open a color picker window:
    - Use `NSColorSampler` (macOS 10.15+) to sample colors from the screen
    - Show the color value at the mouse position (HEX, RGB, HSB)
    - Color history
  - Verification: after clicking, colors can be sampled from anywhere on the screen

- [x] Implement the "Check for Updates" feature (`FreeDisplay/Services/UpdateService.swift`)
  - Implementation hints:
    If released as open source on GitHub, check for new versions with the GitHub Releases API:
    `GET https://api.github.com/repos/{owner}/{repo}/releases/latest`
    Compare `tag_name` with the current version number.
    When there's a new version, show an "Update available" hint at the bottom of the menu.
    For now, a UI placeholder is enough; implement the actual check after it's published to GitHub.
  - Verification: the version number shows at the bottom of the menu

- [x] UI polish and consistency (`global`)
  - Implementation hints:
    Check each item against the BetterDisplay screenshots:
    1. Consistent icon colors for every section (blue circle icons)
    2. Smooth expand/collapse animations
    3. Responsive slider dragging
    4. Dark/light mode support (`@Environment(\.colorScheme)`)
    5. Menu width matching BetterDisplay (about 320 pt)
    6. Matching font sizes and spacing
    7. Shortcut support: ⌥+click the menu bar icon to quickly identify displays
  - Done: added the `MenuItemIcon` colored rounded-square icon helper; every section uses a consistent icon style (semantic colors: red = streaming/PiP, purple = color management, green = lock/protection, orange = auto brightness, etc.); every expand/collapse now has `withAnimation(.easeInOut(duration: 0.2))` + `.transition(.opacity.combined(with: .move(edge: .top)))`.

- [x] Performance optimization (`global`)
  - Implementation hints:
    1. DDC communication: background thread + result cache (5-second TTL)
    2. Stream rendering: Metal instead of CoreImage (if Phase 9 used CIImage)
    3. Menu opening speed: lazy-load areas that aren't visible
    4. Memory: reuse a pool of stream buffers to avoid frequent allocation
    5. Battery: stop capturing when streaming/PiP isn't active
  - Done: DDCService gained `VCPCacheEntry` (5-second TTL) + the `vcpCache` dictionary + the `cacheLock` NSLock; `readAsync` returns cache hits first, `writeAsync` invalidates the matching cache entry after a successful write; `readBatchVCPCodes` fills the cache while reading in bulk.

- [x] Build a distributable .app (`build script`)
  - Done: created `ExportOptions.plist` (unsigned distribution configuration) and `build.sh` (one-step archive → export → DMG packaging).

- [x] Trigger refactor-context to set up the context scaffolding
  - Done: every phase is complete, and CODEMAP and the docs are up to date.

## Phase acceptance

- Every feature works correctly
- Settings are persisted (restored after restart)
- The UI closely matches the BetterDisplay screenshots
- A distributable .app / .dmg can be built
- All tests pass + documentation is complete

**When done**: the project is complete; running project-optimize for a final reflection is recommended
