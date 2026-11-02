# Lessons Learned — IOKit

> Updated: 2026-03-05

## IOKit / DDC

- In the CF dictionary returned by `IODisplayCreateInfoDictionary`, `DisplayVendorID` and `DisplayProductID` are of type `Int` (not `UInt32`); try casting to UInt32 first, then to Int
- `IODisplayCreateInfoDictionary` returns `Unmanaged<CFDictionary>?`; get the value with `.takeRetainedValue()` (ARC-managed)
- The matching parameter of `IOServiceGetMatchingServices` consumes a reference to the CFDictionary, so it doesn't need a manual release
- IOKit's I2C submodule is an `explicit module` that `import IOKit` doesn't include → you need `import IOKit.i2c` (I2C functions) and `import IOKit.graphics` (IODisplay*FloatParameter functions)
- `IOI2CRequest` is inside a `#pragma pack(push, 4)` struct, and the `sendTransactionType`/`replyTransactionType` fields are of type `IOOptionBits` (UInt32, not UInt8)
- `kIODisplayBrightnessKey` is `#define "brightness"`, and Swift doesn't bridge string macros automatically → use `"brightness" as CFString` directly
- Swift's `Array.withUnsafeMutableBytes` holds an exclusive mutable borrow, so the closure can't subscript the original array again → read the data through the raw buffer pointer instead (`replyRaw.bindMemory(to: UInt8.self)`), or capture `.count` outside the closure beforehand
- `IOFBCopyI2CInterfaceForBus(framebuffer, busIndex, &interface)` is a cleaner API than manually looking up the IOFramebufferI2CInterface child node; prefer it
- If a `BrightnessService` method needs to access `@MainActor`-isolated `DisplayInfo` properties, mark it `@MainActor`; the actual DDC I/O runs asynchronously on DDCService's internal ddcQueue and doesn't block the MainActor

## IOKit / Screen rotation (Phase 4)

- `CGDisplayIOServicePort` is fully **unavailable** (not just deprecated) in the latest macOS SDK and errors out directly; you must walk the IOKit registry instead
- Alternative: walk `IODisplayConnect` → match by vendor/model → `IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent)` to get the IOFramebuffer (exactly the same pattern as DDCService.framebufferService)
- Screen rotation: trigger with `IORegistryEntrySetCFProperty(fb, "IOFBTransform", NSNumber(value: index))` + `IOServiceRequestProbe(fb, 0x00000400)`; rotation index = 0/1/2/3 corresponds to 0°/90°/180°/270°
- `import IOKit.graphics` is needed for the graphics constants `IOServiceRequestProbe` requires

## IOKit / Ambient light sensor (Phase 11)

- `AppleLMUController` is an IOKit service, obtained with `IOServiceGetMatchingService`; after opening a connection with `IOServiceOpen`, read the two-channel (left/right) sensor UInt64 values with `IOConnectCallMethod(port, 0, nil, 0, nil, 0, &output, &outputCount, nil, &outputStructSize)`
- The struct size parameter of `IOConnectCallMethod` is an `Int` (size_t = Int in Swift) and can't be `nil` → you must pass `0` or a pointer to a variable (`&outputStructSize`)
- After creating a new Swift file, if other files reference types in it, you must first run `xcodegen generate` to regenerate the xcodeproj; otherwise you get "cannot find in scope"
- When the `init` of an `@MainActor` class accesses properties of another `@MainActor` class, the `init` must also be marked `@MainActor`; otherwise Swift 6 strict concurrency reports an error

## IOKit display matching (Phases 13-15)

### L-003: vendor+model IOKit matching is unreliable
- **Symptom**: the DisplayInfo name shows "Display 2" and the DDC brightness slider has no effect
- **Cause**: the values returned by CGDisplayVendorNumber/ModelNumber don't always match IOKit's DisplayVendorID/DisplayProductID (they don't match on at least the HKC H2435Q), so matching the IODisplayConnect service fails
- **Solution**: use NSScreen.localizedName for the name (a system API, the most reliable); look up the IOKit service with CGDisplayIOServicePort (deprecated but still usable)
- **Lesson**: don't assume different frameworks (CoreGraphics vs IOKit) use the same identifiers for the same hardware. Prefer system-level APIs (NSScreen) over low-level IOKit lookups
- **Date**: 2026-03-03

### L-004: Don't make microsecond-scale operations async
- **Symptom**: Phase 14 made the name lookup in DisplayInfo.init async, so users saw "Display N" flicker before it updated to the real name (and sometimes it never updated)
- **Cause**: the IOKit name lookup takes only microseconds, and making it async introduced a race condition (refreshDisplays may be called several times, and a later call overwrites an earlier call's async result)
- **Solution**: roll back to a synchronous call
- **Lesson**: async is only worth it for genuinely slow operations (>100 ms). Making microsecond-scale operations async just adds complexity and bugs
- **Date**: 2026-03-03

## Apple Silicon DDC (Phase 17)

### L-005: The IOFramebuffer I2C API doesn't work at all on Apple Silicon
- **Symptom**: DDC brightness/contrast control has no effect on any external display
- **Cause**: `IOFBCopyI2CInterfaceForBus` / `IOI2CSendRequest` are Intel-era IOFramebuffer APIs; on Apple Silicon (M1/M2/M3/M4) these calls return silently without sending any I2C data
- **Solution**: use the IOAVService private API (`IOAVServiceCreateWithService` + `IOAVServiceWriteI2C` / `IOAVServiceReadI2C`), finding external displays through the DCPAVServiceProxy IOKit service
- **Lesson**: macOS uses completely different display communication APIs on different CPU architectures. MonitorControl and BetterDisplay both use IOAVService. See alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
- **Date**: 2026-03-03

### L-033: Built-in brightness on Apple Silicon needs DisplayServices, not CoreDisplay or IOKit
- **Symptom**: the built-in brightness slider changed only the UI; Auto Brightness synced external displays to 100% whatever the built-in display was at
- **Cause**: there are no IODisplayConnect services and CGDisplayIOServicePort is 0 on Apple Silicon, so IODisplayGet/SetFloatParameter has nothing to talk to. `CoreDisplay_Display_GetUserBrightness` always returned 1.0 and `SetUserBrightness` did nothing (probe on M4 Pro, macOS 27, real brightness 0.69)
- **Solution**: `DisplayServicesGetBrightness(id, &float)` / `DisplayServicesSetBrightness(id, float)` from `/System/Library/PrivateFrameworks/DisplayServices.framework`, loaded with dlsym. Both return 0 on success and an error (1000) for external displays. IOKit stays as the Intel fallback
- **Lesson**: before trusting a private getter, compare it with another source; a symbol that resolves and returns a plausible value can still be a no-op
- **Date**: 2026-11-02

### L-035: Validate DDC/CI replies; one failure isn't "no DDC"
- **Symptom**: garbage replies (e.g. all 0xFF) read as max = 65535 and marked DDC as working; one failed read/write after hot-plug or wake switched a monitor to software dimming until it was unplugged
- **Cause**: `arm64Read` trusted bytes 6–9 blindly; BrightnessService set `ddcAvailable = false` on the first failure and never retried
- **Solution**: `DDCService.parseVCPReply` checks opcode 0x02, result 0x00, echoed VCP code, checksum (`0x50 XOR bytes 0–9 == byte 10`, confirmed on a live monitor) and max > 0. BrightnessService needs 3 failed operations in a row, retries launch/wake probes every 2 s, resets DDC state on wake, and clears leftover software dimming whenever DDC succeeds
- **Date**: 2026-11-02
