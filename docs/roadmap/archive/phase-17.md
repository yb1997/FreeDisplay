# Phase 17: Targeted core feature fixes — DDC/HiDPI/notch

> Goal: fix three technical problems that hurt the core experience: DDC brightness control not working on Apple Silicon, HiDPI virtual display creation failing for the external 2K display, and the notch overlay NSWindow crashing

## Prerequisites

This phase involves the private API bridging header and rewrites of two low-level services, and the tasks have a dependency order:
**Task 1 (bridging header) must come before Tasks 2 and 3**; Task 4 (notch crash) is independent and can start in parallel with Task 1; Task 5 (integration testing) comes last.

---

## Task list

- [x] **Task 1**: Create the Objective-C bridging header (a shared prerequisite for the DDC + virtual display private APIs)
  - Implementation hints:
    1. Create `FreeDisplay/FreeDisplay-Bridging-Header.h` in the project root, declaring the following:

       ```objc
       // ── CGVirtualDisplay private classes (macOS 14+ virtual displays) ──────────────────────
       #import <Foundation/Foundation.h>
       #import <CoreGraphics/CoreGraphics.h>

       @interface CGVirtualDisplayDescriptor : NSObject
       @property (nonatomic) uint32_t sizeInMillimeters;   // diagonal size (millimeters)
       @property (nonatomic) CGSize   maxPixelSize;        // maximum pixel resolution
       @property (nonatomic) CGColorSpaceRef colorSpace;
       @property (nonatomic) NSPoint  whitePoint;
       @property (nonatomic) NSPoint  redPrimary;
       @property (nonatomic) NSPoint  greenPrimary;
       @property (nonatomic) NSPoint  bluePrimary;
       @end

       @interface CGVirtualDisplaySettings : NSObject
       @property (nonatomic) BOOL hiDPI;
       - (void)addMode:(CGSize)size refreshRate:(double)hz;
       @end

       @interface CGVirtualDisplayMode : NSObject
       @property (nonatomic, readonly) CGSize  size;
       @property (nonatomic, readonly) double  refreshRate;
       @property (nonatomic, readonly) BOOL    hiDPI;
       @end

       @interface CGVirtualDisplay : NSObject
       - (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
       - (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
       @property (nonatomic, readonly) CGDirectDisplayID displayID;
       @end

       // ── CGSDisplayMode (advanced resolution switching) ──────────────────────────────────────
       typedef struct {
           uint32_t modeID;
           uint32_t width;
           uint32_t height;
           uint32_t depth;
           double   refreshRate;
           uint32_t flags;        // bit 0x20000 = HiDPI
       } CGSDisplayMode;

       extern CGError CGSConfigureDisplayMode(CGSConnectionID connection, CGDirectDisplayID display, uint32_t modeID);
       extern CGSConnectionID CGSMainConnectionID(void);

       // ── CoreDisplay (optional, for future reference) ────────────────────────────────────────
       // extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);

       // ── IOAVService (Apple Silicon DDC) ──────────────────────────────────────
       typedef void * IOAVServiceRef;
       extern IOAVServiceRef IOAVServiceCreate(CFAllocatorRef allocator);
       extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
       extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service,
                                          uint32_t chipAddress,
                                          uint32_t offset,
                                          void *outputBuffer,
                                          uint32_t outputBufferSize);
       extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service,
                                           uint32_t chipAddress,
                                           uint32_t dataAddress,
                                           void *inputBuffer,
                                           uint32_t inputBufferSize);
       ```

    2. Open `project.yml` and add under `targets.FreeDisplay.settings.base`:
       ```yaml
       SWIFT_OBJC_BRIDGING_HEADER: FreeDisplay/FreeDisplay-Bridging-Header.h
       ```
    3. Run `cd ~/Desktop/FreeDisplay && xcodegen generate`
    4. Run the verification chain to confirm it builds (an unused bridging header shouldn't cause errors either)
  - Verification: `xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5` shows `BUILD SUCCEEDED`

---

- [x] **Task 2**: Rewrite DDCService to support Apple Silicon (IOAVService path)
  - Background: the existing `IOFBCopyI2CInterfaceForBus` + `IOI2CSendRequest` are Intel-era APIs that don't work at all on Apple Silicon. A new ARM64 path is needed, keeping the Intel path as a fallback (for Hackintosh/VM users).
  - Implementation hints:
    1. **Add an ARM64 DDC write method** (`DDCService.swift`):
       ```swift
       // At the top of DDCService, the ARM64-only path
       #if arch(arm64)
       private func findAVService(for displayID: CGDirectDisplayID) -> IOAVServiceRef? {
           // 1. Get the IOService for the display with CGDisplayIOServicePort
           let port = CGDisplayIOServicePort(displayID)
           guard port != IO_OBJECT_NULL else { return nil }

           // 2. Walk up the IORegistry parent nodes to find DCPAVServiceProxy
           var iterator: io_iterator_t = 0
           let matchDict = IOServiceMatching("DCPAVServiceProxy")
           IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
           defer { IOObjectRelease(iterator) }

           var service = IOIteratorNext(iterator)
           while service != IO_OBJECT_NULL {
               defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
               let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service)
               // Confirm it's the right AVService with a harmless test read
               var testBuf = [UInt8](repeating: 0, count: 12)
               let ret = IOAVServiceReadI2C(avService, 0x37, 0x51, &testBuf, 12)
               if ret == kIOReturnSuccess { return avService }
           }
           return nil
       }

       /// ARM64 DDC write: writes a VCP value to the external display (e.g. brightness VCP=0x10)
       private func arm64Write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool {
           guard let avService = findAVService(for: displayID) else { return false }
           // DDC/CI write packet format (note: dataAddress=0x51 is passed as a parameter, not put in the buffer)
           // buffer: [0x84, 0x03, vcpCode, valueHigh, valueLow, checksum]
           let valueHigh = UInt8((value >> 8) & 0xFF)
           let valueLow  = UInt8(value & 0xFF)
           var checksum  = UInt8(0x50 ^ 0x03 ^ command ^ valueHigh ^ valueLow)
           // 0x50 = 0x51 XOR'd with 0x01 (reply flag) — see the DDC/CI spec
           var buf: [UInt8] = [0x84, 0x03, command, valueHigh, valueLow, checksum]
           let ret = IOAVServiceWriteI2C(avService, 0x37, 0x51, &buf, UInt32(buf.count))
           return ret == kIOReturnSuccess
       }

       /// ARM64 DDC read: reads the current VCP value
       private func arm64Read(displayID: CGDirectDisplayID, command: UInt8) -> (current: UInt16, max: UInt16)? {
           guard let avService = findAVService(for: displayID) else { return nil }
           // First send the VCP request packet (similar to write, opcode=0x01)
           var requestChecksum = UInt8(0x51 ^ 0x82 ^ 0x01 ^ command)
           var requestBuf: [UInt8] = [0x82, 0x01, command, requestChecksum]
           IOAVServiceWriteI2C(avService, 0x37, 0x51, &requestBuf, UInt32(requestBuf.count))
           // Wait for DDC to process it
           Thread.sleep(forTimeInterval: 0.04)
           // Read the response
           var replyBuf = [UInt8](repeating: 0, count: 12)
           let ret = IOAVServiceReadI2C(avService, 0x37, 0x51, &replyBuf, 12)
           guard ret == kIOReturnSuccess else { return nil }
           // replyBuf format: [len, 0x02, vcpCode, 0x00, maxHigh, maxLow, curHigh, curLow, ...]
           let maxVal  = UInt16(replyBuf[4]) << 8 | UInt16(replyBuf[5])
           let curVal  = UInt16(replyBuf[6]) << 8 | UInt16(replyBuf[7])
           return (curVal, maxVal)
       }
       #endif
       ```

    2. **Change the dispatch logic in `write(displayID:command:value:)`**:
       ```swift
       func write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool {
           #if arch(arm64)
           if arm64Write(displayID: displayID, command: command, value: value) {
               return true
           }
           // When arm64 fails, optionally fall back to the software path
           return false
           #else
           return intelWrite(displayID: displayID, command: command, value: value)
           #endif
       }
       ```
       Rename the existing Intel path methods to `intelWrite` / `intelRead` (same function signatures, only the names change).

    3. **Add a software brightness fallback to `BrightnessService.swift`**:
       - Add a `var isDDCAvailable: [CGDirectDisplayID: Bool] = [:]` cache
       - In `setBrightness(for:value:)`: try the DDC write first; if it fails and it's an external display, call `applyGammaFallback(displayID:brightness:)` to simulate brightness with `CGSetDisplayTransferByTable`
       - `applyGammaFallback` implementation: build a linear ramp from 0 to `brightness` (0.0-1.0) and write it to the gamma table, which looks visually equivalent to lowering brightness (the black level stays put while the white level drops)
       - After recording `isDDCAvailable[displayID] = false`, go straight to the software path from then on without trying DDC again

    4. **Add a mode indicator to `BrightnessSliderView.swift`** (optional but recommended):
       - Add a small label next to the slider title: "DDC" (blue) when DDC is available, "Software" (gray) in software mode
       - Implementation: read the state from `BrightnessService.shared.isDDCAvailable[display.id]`

  - File: `FreeDisplay/Services/DDCService.swift` (add the `#if arch(arm64)` block, rename the existing Intel code)
  - File: `FreeDisplay/Services/BrightnessService.swift` (add the software fallback logic)
  - File: `FreeDisplay/Views/BrightnessSliderView.swift` (optional: the mode indicator label)
  - References: MonitorControl `Arm64DDC.swift`, the `m1ddc` project, alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
  - Verification: drag the external display's brightness slider → the display's brightness actually changes (DDC succeeded); for a display that doesn't support DDC → it falls back to software dimming automatically, the slider still works, and the label shows "Software"

---

- [x] **Task 3**: Implement real virtual display creation (CGVirtualDisplay API)
  - Background: `create(config:)` and `destroy(id:)` in `VirtualDisplayService.swift` currently only return a placeholder `false`, so the HiDPI virtual display feature doesn't work at all. They need to be implemented with the private `CGVirtualDisplay` classes exposed by the bridging header.
  - Implementation hints:
    1. **Implement `create(config:)` in `VirtualDisplayService.swift`**:
       ```swift
       // Keep a strong reference; releasing it = the virtual display disappears
       private var activeDisplayObjects: [CGDirectDisplayID: CGVirtualDisplay] = [:]

       func create(config: VirtualDisplayConfig) -> CGDirectDisplayID? {
           let descriptor = CGVirtualDisplayDescriptor()
           descriptor.sizeInMillimeters = 527  // a 24-inch diagonal is about 527 mm (can be adjusted per config)
           descriptor.maxPixelSize = CGSize(width: CGFloat(config.width), height: CGFloat(config.height))
           descriptor.colorSpace   = CGColorSpace(name: CGColorSpace.sRGB)!
           // sRGB gamut reference values
           descriptor.whitePoint   = NSPoint(x: 0.3127, y: 0.3290)
           descriptor.redPrimary   = NSPoint(x: 0.6400, y: 0.3300)
           descriptor.greenPrimary = NSPoint(x: 0.3000, y: 0.6000)
           descriptor.bluePrimary  = NSPoint(x: 0.1500, y: 0.0600)

           let settings = CGVirtualDisplaySettings()
           settings.hiDPI = config.hiDPI
           // Add the main mode (actual pixel size)
           settings.addMode(CGSize(width: CGFloat(config.width), height: CGFloat(config.height)),
                            refreshRate: Double(config.refreshRate))
           // If hiDPI, also add the logical resolution mode (half the physical size)
           if config.hiDPI {
               settings.addMode(CGSize(width: CGFloat(config.width / 2),
                                       height: CGFloat(config.height / 2)),
                                refreshRate: Double(config.refreshRate))
           }

           let virtualDisplay = CGVirtualDisplay(descriptor: descriptor)
           guard virtualDisplay.applySettings(settings) else { return nil }
           let displayID = virtualDisplay.displayID
           guard displayID != kCGNullDirectDisplay else { return nil }
           activeDisplayObjects[displayID] = virtualDisplay  // keep a strong reference
           return displayID
       }

       func destroy(id: CGDirectDisplayID) {
           activeDisplayObjects.removeValue(forKey: id)  // release → the virtual display disappears
       }
       ```

    2. **Implement `enableHiDPIVirtual(for:physicalWidth:physicalHeight:)`**:
       ```swift
       /// Creates a 2x virtual display for a physical external display and mirrors it, giving HiDPI scaling
       func enableHiDPIVirtual(for displayID: CGDirectDisplayID,
                                physicalWidth: Int,
                                physicalHeight: Int) -> CGDirectDisplayID? {
           let config = VirtualDisplayConfig(
               name: "HiDPI Virtual",
               width: physicalWidth * 2,   // 2x the physical resolution, e.g. 2K→4K
               height: physicalHeight * 2,
               refreshRate: 60,
               hiDPI: true
           )
           guard let virtualID = create(config: config) else { return nil }
           // Mirror the physical display to the virtual display (physical as the mirror source, virtual as the mirror target)
           MirrorService.shared.startMirror(source: displayID, target: virtualID)
           return virtualID
       }
       ```

    3. **Implement `disableHiDPIVirtual(for:)`**:
       ```swift
       func disableHiDPIVirtual(for physicalDisplayID: CGDirectDisplayID) {
           // Find the virtual display associated with this physical display
           guard let virtualID = hiDPIVirtualMap[physicalDisplayID] else { return }
           MirrorService.shared.stopMirror(for: virtualID)
           destroy(id: virtualID)
           hiDPIVirtualMap.removeValue(forKey: physicalDisplayID)
       }
       // VirtualDisplayService needs a new: private var hiDPIVirtualMap: [CGDirectDisplayID: CGDirectDisplayID] = [:]
       // After enableHiDPIVirtual returns virtualID, record: hiDPIVirtualMap[displayID] = virtualID
       ```

    4. **Update `HiDPIService.swift`**:
       - Change `enableHiDPI(for:)` to try the virtual display path first (`VirtualDisplayService.shared.enableHiDPIVirtual`)
       - If that fails (e.g. insufficient permissions), fall back to the plist override path
       - Distinguish the two paths in the UI: the virtual display path takes effect immediately, while the plist path requires reconnecting the display

  - File: `FreeDisplay/Services/VirtualDisplayService.swift` (the main implementation, replacing the placeholder false)
  - File: `FreeDisplay/Services/HiDPIService.swift` (switch the primary/fallback paths)
  - Note: the `CGVirtualDisplay` object must be held by a strong reference (stored in the `activeDisplayObjects` dictionary); as soon as ARC releases it, the virtual display disappears immediately
  - Note: `CGVirtualDisplayDescriptor.colorSpace` is a `CGColorSpaceRef` (Core Foundation); in Swift, create it with `CGColorSpace(name:)` and assign it directly, without a manual retain
  - References: the BetterDummy project's bridging header, the KhaosT/CGVirtualDisplay example
  - Verification: turn the HiDPI toggle on → a new "HiDPI Virtual" display appears in the system display list → scaled modes such as `1920×1080 (HiDPI)` appear in the resolution list → turn the toggle off → the virtual display disappears

---

- [x] **Task 4**: Fix the notch overlay window crash (NSWindow lifecycle)
  - Background: the `NSWindow` created by `NotchOverlayManager` is missing `isReleasedWhenClosed = false`, so Swift holds a dangling pointer after it closes; `@State isHidingNotch` is out of sync with the manager's state; a new window is created before the old one is closed, causing ordering problems; and `onChange` uses the deprecated single-parameter form.
  - Implementation hints:
    1. **`NotchOverlayManager.swift`** — window creation fix:
       ```swift
       // In the showOverlay(for:) method, add right after the window is initialized:
       window.isReleasedWhenClosed = false  // ← key: prevents a dangling pointer after close()
       ```

    2. **`NotchOverlayManager.swift`** — close ordering fix:
       ```swift
       func showOverlay(for screen: NSScreen) {
           // Close the old window first, then create the new one
           if let existing = overlayWindows[screen.displayID] {
               existing.close()
               overlayWindows.removeValue(forKey: screen.displayID)
           }
           // ... then create the new window
       }
       ```

    3. **`NotchOverlayManager.swift`** — add a query method:
       ```swift
       public func isShowingOverlay(for screen: NSScreen) -> Bool {
           return overlayWindows[screen.displayID] != nil
       }
       ```

    4. **`NotchView.swift`** — state sync fix:
       ```swift
       // Sync the initial state from the manager in body or .onAppear:
       .onAppear {
           isHidingNotch = NotchOverlayManager.shared.isShowingOverlay(for: screen)
       }
       ```

    5. **`NotchView.swift`** — deprecated onChange API fix:
       ```swift
       // Old (deprecated single-parameter form):
       // .onChange(of: isHidingNotch) { newValue in ... }
       // Change to the two-parameter form:
       .onChange(of: isHidingNotch) { _, newValue in
           // the handling logic stays the same
       }
       ```

  - File: `FreeDisplay/Services/NotchOverlayManager.swift`
  - File: `FreeDisplay/Views/NotchView.swift` (if it exists; otherwise change the View file that contains the notch Toggle)
  - Verification: toggle the notch switch ON/OFF ten times → no crash; close the menu and reopen it → the notch switch state matches the actual overlay state; no EXC_BAD_ACCESS or objc over-release logs in Console.app

---

- [x] **Task 5**: Integration testing and UI updates
  - Implementation hints:
    1. **DDC verification**: connect the external HKC H2435Q → open FreeDisplay → drag the brightness slider → watch whether the display's physical brightness changes (judge by eye, or check whether the DDC readback in IntegratedControlView echoes the value)
    2. **HiDPI verification**: external 2K display → turn on the HiDPI toggle → check in System Settings "Displays" whether a new virtual display appears → whether `1920×1080 (Retina)` appears in the resolution list → choose that resolution → whether text is noticeably sharper
    3. **Notch verification**: built-in MacBook screen → notch toggle ON → the overlay appears → OFF → the overlay disappears → repeat 10 times → no crash; close the menu and reopen it → the state matches
    4. **Update `DisplayDetailView.swift` / `MenuBarView.swift`** (as needed):
       - If DDC falls back to software, show a software mode hint in the brightness control area
       - If the HiDPI virtual display is active, show an "HiDPI enabled (virtual display)" status
    5. **Update `docs/BLOCKING.md`**:
       - Mark B-002 (DDC unavailable on Apple Silicon) as resolved and move it to the "Resolved" section
       - Mark B-003 (HiDPI virtual display creation fails) as resolved and move it to the "Resolved" section
  - File: `FreeDisplay/Views/DisplayDetailView.swift` (small changes as needed)
  - File: `FreeDisplay/Views/MenuBarView.swift` (small changes as needed)
  - File: `docs/BLOCKING.md` (move the resolved items)
  - Verification: see the three manual tests above; builds with no warnings and no errors

---

## Phase acceptance

```bash
# 1. Build check
cd ~/Desktop/FreeDisplay && xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5

# 2. Manual test checklist:
# [ ] DDC: external display brightness slider → the screen brightness actually changes (or the software mode label shows correctly)
# [ ] HiDPI: HiDPI toggle ON → the virtual display appears → 1920x1080@2x is selectable → OFF → the virtual display disappears
# [ ] Notch: notch toggle ON/OFF × 10 times → no crash → the state matches the overlay
# [ ] Menu reopen: every toggle state above stays correct after closing and reopening the menu
```

**Phase acceptance criteria**: builds + all four manual tests above are satisfied
