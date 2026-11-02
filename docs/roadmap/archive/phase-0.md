# Phase 0: Project initialization ⏳

> Run automatically by project-planner

## Task list

- [ ] Create the project directory structure
  ```
  FreeDisplay/
  ├── project.yml                    # xcodegen project configuration
  ├── FreeDisplay/
  │   ├── App/
  │   │   ├── FreeDisplayApp.swift   # @main entry point, MenuBarExtra
  │   │   └── AppDelegate.swift      # NSApplicationDelegate, permission requests
  │   ├── Views/                     # SwiftUI view layer
  │   ├── ViewModels/                # ViewModel layer
  │   ├── Models/                    # Data models
  │   ├── Services/                  # Low-level services (DDC, display management, etc.)
  │   ├── Utilities/                 # Utility functions
  │   ├── Resources/
  │   │   └── Assets.xcassets/       # Icon resources
  │   └── FreeDisplay.entitlements   # Permission declarations
  └── docs/
      └── roadmap/                   # Where this file lives
  ```
  - Implementation hint: create every directory with `mkdir -p`

- [ ] Create `project.yml` (xcodegen configuration)
  - Implementation hint: configure a macOS app target with a minimum deployment of macOS 14.0, App Sandbox turned off,
    Hardened Runtime configured, linking IOKit.framework, CoreGraphics.framework,
    ScreenCaptureKit.framework, and ColorSync.framework.
    Point the entitlements file at FreeDisplay/FreeDisplay.entitlements
  - Verification: `xcodegen generate` successfully generates FreeDisplay.xcodeproj

- [ ] Create `FreeDisplay/FreeDisplay.entitlements`
  - Implementation hint: turn off App Sandbox (`com.apple.security.app-sandbox` = false),
    and turn on the Hardened Runtime-related permissions
  - Verification: the file exists and is valid XML

- [ ] Create `FreeDisplay/App/FreeDisplayApp.swift`
  - Implementation hint: use `@main` + the SwiftUI `App` protocol,
    create the menu bar icon with `MenuBarExtra("FreeDisplay", systemImage: "display")`,
    and for now put a "FreeDisplay v0.1" text + a "Quit" button in the menu.
    Set `.menuBarExtraStyle(.window)` to support custom views.
  - Verification: after building and running, a display icon appears in the menu bar, and clicking it opens a panel

- [ ] Create `FreeDisplay/App/AppDelegate.swift`
  - Implementation hint: an `NSApplicationDelegate` that hides the Dock icon in `applicationDidFinishLaunching`
    (`NSApp.setActivationPolicy(.accessory)`)
  - Verification: after running, there's no Dock icon; the app is visible only in the menu bar

- [ ] Create `FreeDisplay/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
  - Implementation hint: use the standard Contents.json template for a macOS app icon set, without any actual icon files for now
  - Verification: no asset catalog warnings when xcodegen generates the project

- [ ] Create skeleton files (with TODO comments)
  - `FreeDisplay/Models/DisplayInfo.swift`: `class DisplayInfo: ObservableObject, Identifiable` stores a single display's info
  - `FreeDisplay/Services/DisplayManager.swift`: `class DisplayManager: ObservableObject` manages every display
  - `FreeDisplay/Services/DDCService.swift`: `class DDCService` DDC/CI I2C communication
  - `FreeDisplay/Views/MenuBarView.swift`: main menu view skeleton
  - Each file contains the imports, the class declaration, the key method signatures + `// TODO: Phase N` comments

- [ ] Generate the Xcode project with xcodegen and build it
  - Implementation hint: `cd ~/Desktop/FreeDisplay && xcodegen generate && xcodebuild -scheme FreeDisplay -configuration Debug build`
  - Verification: `xcodebuild build` succeeds with no build errors

## Phase acceptance

```bash
cd ~/Desktop/FreeDisplay
xcodegen generate   # successfully generates the .xcodeproj
xcodebuild -scheme FreeDisplay -configuration Debug build  # builds successfully
# After running: a display icon appears in the menu bar, and clicking it shows "FreeDisplay v0.1" + a Quit button
```
