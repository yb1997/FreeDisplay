# Blocking Issues — FreeDisplay

> Updated: 2026-03-02 | **Read before starting work; unresolved P0/P1 issues must be handled first**

## Scheduling rules

1. After reading this file → if there are P0/P1 issues → **resolve them one by one from highest to lowest priority, and only work on the ROADMAP once they're all cleared**
2. If there are only P2 issues → you can work on ROADMAP tasks first and fit the P2s in between
3. Once resolved → move it to the "Resolved" section below and write down the solution
4. When you get stuck on a new problem during work → add it here immediately

---

## 🔴 P0 — Hard blockers

(None)

---

## 🟡 P1 — High priority

(None)

---

## 🔵 P2 — Normal priority

(None)

---

## ✅ Resolved

### ~~B-004: HiDPI virtual display triggers the system mirroring UI + mouse movement stutter~~
- **Solution**: `CGConfigureDisplayMirrorOfDisplay` triggers hardware mirroring mode on Apple Silicon, which is a dead end. Switched to the same plist override approach BetterDisplay uses: write `scale-resolutions` to `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-XXXX`. This needs administrator privileges (NSAppleScript), and takes effect after the display is reconnected. Removed all mirroring-related code (enableHiDPIVirtual/disableHiDPIVirtual/hiDPIMirrorMap, etc.).
- **Resolved on**: 2026-03-05
- **Lesson**: macOS HiDPI has only two approaches: (1) plist override (the BetterDisplay approach, needs admin + reconnect) (2) a pure CGVirtualDisplay virtual display (not mirrored with a physical display). ❌ Never use CGConfigureDisplayMirrorOfDisplay.

### ~~B-002: CGVirtualDisplay is a private API with no public header~~
- **Solution**: The user approved using the private API. Created FreeDisplay-Bridging-Header.h declaring the CGVirtualDisplay + IOAVService interfaces; VirtualDisplayService now fully implements virtual display creation/destruction.
- **Resolved on**: 2026-03-03

### ~~B-003: DDC brightness control doesn't work on some external displays~~
- **Solution**: Root cause confirmed: the IOFramebuffer I2C API that DDCService used doesn't work at all on Apple Silicon. Added an IOAVService ARM64 DDC path (finding external displays through DCPAVServiceProxy), and added a CGSetDisplayTransferByTable gamma-table software brightness fallback.
- **Resolved on**: 2026-03-03

### ~~B-001: DisplayInfo.name shows only "Display N" instead of the real display name~~
- **Solution**: Use `IOServiceMatching("IODisplayConnect")` + `IODisplayCreateInfoDictionary` to enumerate every IODisplayConnect service, match by DisplayVendorID + DisplayProductID, and take the product name for the first locale from the DisplayProductName dictionary; the built-in display returns "Built-in Display" directly
- **Resolved on**: 2026-03-02
- **Lesson**: Integer values in IOKit CF dictionaries may be Int rather than UInt32, so try both types

### ~~B-000: Missing GENERATE_INFOPLIST_FILE causes the build to fail~~
- **Solution**: Add `GENERATE_INFOPLIST_FILE: YES` to the settings in project.yml
- **Resolved on**: 2026-03-02
- **Lesson**: xcodegen doesn't generate Info.plist automatically; it has to be enabled explicitly

### ~~B-000b: Swift 6 concurrency error on the DDCService static singleton~~
- **Solution**: Mark the class `@unchecked Sendable`, and set `SWIFT_STRICT_CONCURRENCY: minimal` in project.yml
- **Resolved on**: 2026-03-02
- **Lesson**: Under Swift 6 strict concurrency checking, singletons must be explicitly marked Sendable
