# Phase 20: Release preparation

> Status: Complete | Estimate: medium complexity

## Goal

Package FreeDisplay from its development state into a distributable, production macOS app, including an icon, code cleanup, a DMG installer, and a GitHub Release.

## Tasks

### Task 1: Code cleanup + App icon
- [x] Delete the deprecated `HiDPIPresetRow` from MenuBarView (replaced by PresetListView)
- [x] Search for and clean up other unused code/dead code
- [x] Generate the App icon with a Python PIL/Pillow script: rounded-rectangle display + the letter "F" + blue-purple gradient
- [x] Generate every size in AppIcon.appiconset (16/32/64/128/256/512/1024)
- [x] Create `FreeDisplay/Assets.xcassets/AppIcon.appiconset/Contents.json` + the PNG files
- [x] Update project.yml to reference the AppIcon asset catalog

**Implementation hint**: Generate a 1024×1024 PNG with a Python script and scale each size with `sips -z H W`. project.yml needs `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` added.

### Task 2: Launch at Login (SMAppService)
- [x] Move the existing implementation in `LaunchService.swift` to `SMAppService.mainApp` (macOS 13+)
- [x] Replace the old API with `register()` / `unregister()`; needs `import ServiceManagement`
- [x] Confirm the existing `fd.launchAtLogin` toggle in SettingsService works with it
- [x] First-launch prompt: if `fd.launchAtLogin` has never been set, show a one-time prompt

**Implementation hint**: `SMAppService.mainApp.register()` is a single line of code. Check the status with `.status == .enabled`.

### Task 3: Release build + ad-hoc signing + DMG packaging
- [x] Create the one-step script `scripts/build-dmg.sh`
- [x] Release build: `xcodebuild -scheme FreeDisplay -configuration Release build`
- [x] Ad-hoc signing: `codesign --force --deep --sign - FreeDisplay.app` (the minimum requirement without a Developer ID)
- [x] Package the DMG with `hdiutil`: FreeDisplay.app + Applications shortcut
- [x] Explain in the README that the first launch needs right-click → Open (to get past Gatekeeper)

**Implementation hint**: `hdiutil create -volname "FreeDisplay" -srcfolder build/ -ov -format UDZO FreeDisplay.dmg`. An app without a Developer ID signature has to be trusted manually by the user.

### Task 4: README + CHANGELOG + GitHub Release script
- [x] Write README.md: project introduction, feature list, installation instructions, screenshot placeholders, Gatekeeper bypass instructions
- [x] Write CHANGELOG.md: summarize the major changes from Phases 0-20
- [x] Create `scripts/release.sh`: build → sign → package DMG → `gh release create`
- [x] Add a download badge to the README

**Implementation hint**: Screenshots must be taken manually with `screencapture` after running the app; use placeholders for now. `gh release create v1.0.0 --title "FreeDisplay v1.0.0" --notes-file CHANGELOG.md *.dmg`.

### Task 5: UpdateService improvements
- [x] Confirm the UpdateService update check logic points at the GitHub Releases API
- [x] Use the placeholder URL `https://api.github.com/repos/OWNER/FreeDisplay/releases/latest` (the user replaces it when publishing)
- [x] Show a download link in the menu bar when a new version is detected
- [x] Confirm the "Check for Updates at Launch" toggle in settings works

**Implementation hint**: The GitHub Releases API returns JSON; parse `tag_name` and compare it with the current `CFBundleShortVersionString`.

## Acceptance criteria

```bash
# Release build
xcodebuild -scheme FreeDisplay -configuration Release build 2>&1 | tail -3

# DMG packaging
./scripts/build-dmg.sh

# Verification
# 1. Double-click the DMG to install → drag to Applications → launches normally
# 2. The App icon shows correctly in the Dock/Finder
# 3. The Launch at Login toggle works
# 4. README/CHANGELOG content is complete
```
