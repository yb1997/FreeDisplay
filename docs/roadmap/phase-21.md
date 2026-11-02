# Phase 21: Feature trimming — remove unused features

> Status: Complete | Estimate: medium complexity

## Goal

Remove impractical features (rotation, streaming/PiP, color mode inversion, mirroring UI), slim down the codebase, and reduce the maintenance burden.

## Tasks

### Task 1: Remove the rotation feature
- [x] Delete `Services/RotationService.swift`
- [x] Delete `Views/RotationView.swift`
- [x] `DisplayDetailView.swift`: remove the `showRotation` state, the rotation DetailRow, the RotationView embed, and loadExpanded/saveExpanded("rotation")
- [x] `DisplayInfo.swift`: remove the `rotation: Double` property (grep to confirm there are no other references)
- [x] `ConfigProtectionService.swift`: remove the `RotationService.shared.setRotation` calls (about 2 places), the `ProtectedItems.rotation` field, and the `DisplayConfig.rotation` field
- [x] `ConfigProtectionView.swift`: remove the rotation protection toggle

**Implementation hint**: First grep `RotationService\|RotationView\|\.rotation` to find every reference, then clean them up one by one.

### Task 2: Remove streaming + PiP + video filters
- [x] Delete `Services/ScreenCaptureService.swift`
- [x] Delete `ViewModels/StreamViewModel.swift`
- [x] Delete `Views/StreamControlView.swift`
- [x] Delete `Views/StreamWindow.swift`
- [x] Delete `Views/PiPControlView.swift`
- [x] Delete `Views/PiPWindow.swift`
- [x] Delete `Views/VideoFilterWindow.swift`
- [x] `DisplayDetailView.swift`: remove the `showStream` and `showPiP` states + their DetailRows + embeds
- [x] `MenuBarView.swift`: remove VideoFilterMenuEntry and SystemColorMenuEntry (if present)

**Implementation hint**: These 7 files are isolated; after deleting them, grep `ScreenCaptureService\|StreamViewModel\|StreamControlView\|PiPControlView\|PiPWindow\|VideoFilter` to confirm no references remain.

### Task 3: Remove color modes (inversion/grayscale) and the mirroring UI
- [x] Delete `Views/ColorModeView.swift`
- [x] Delete `Views/MirrorView.swift` (keep `Services/MirrorService.swift`; HiDPI depends on it)
- [x] `DisplayDetailView.swift`: remove the `showColorMode` and `showMirror` states + their DetailRows + embeds
- [x] `DisplayDetailView.swift`: clean up the `colorModeDesc` state (keep `colorSpaceName`; ColorProfile needs it)

**Implementation hint**: Don't delete MirrorService.swift! VirtualDisplayService's HiDPI feature depends on MirrorService.enableMirror/disableMirror.

### Task 4: Build verification + cleanup
- [x] `xcodegen generate && xcodebuild -scheme FreeDisplay -configuration Debug build`
- [x] Update `docs/CODEMAP.md`: remove the entries for deleted files
- [x] Update `README.md`: remove the deleted features from the feature list
- [x] Update `CHANGELOG.md`: add a v1.1.0 entry recording the feature trimming

## Acceptance criteria

```bash
# Build passes
xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -3

# Confirm the files are deleted
ls FreeDisplay/Services/RotationService.swift 2>&1  # should not exist
ls FreeDisplay/Views/RotationView.swift 2>&1         # should not exist
ls FreeDisplay/Views/StreamControlView.swift 2>&1    # should not exist

# Confirm no references remain
grep -r "RotationService\|RotationView\|StreamControlView\|PiPControlView\|ColorModeView\|MirrorView" FreeDisplay/ --include="*.swift" | grep -v "^Binary"
# should return nothing
```
