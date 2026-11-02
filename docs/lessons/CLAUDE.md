# Lessons Learned Index — FreeDisplay

> Updated: 2026-03-05

## Topic index

| Topic | File | Entries |
|------|------|------|
| IOKit / DDC / rotation / ambient light / display matching / Apple Silicon | [iokit.md](iokit.md) | L-003, L-004, L-005, L-033, L-035 + general entries |
| CoreGraphics / HiDPI / CGVirtualDisplay | [coregraphics.md](coregraphics.md) | L-006, L-007, L-020 ~ L-027, L-030, L-031, L-036, L-037 + general entries |
| SwiftUI / MenuBarExtra / UI animation / DDC cache / performance / localization | [swiftui.md](swiftui.md) | L-032 + general entries |
| Cross-Service coordination / concurrency / resource management / signing and permissions | [services.md](services.md) | L-008 ~ L-019, L-028, L-029, L-034 |
| Xcode build / phase wrap-up | [build.md](build.md) | General entries |

## Permanent rules (frequent pitfalls)

1. **After adding a Swift source file you must run `xcodegen generate`** — otherwise the compiler doesn't know about the new file ("cannot find in scope")
2. **Two Services must not each write the same CoreGraphics resource** — designate a single writer; the others influence it through its interface (see services.md L-008)
3. **When passing self to a C callback, always use `Unmanaged.passRetained` and pair it with a release on unregister** — passUnretained is a dangling-pointer time bomb
4. **❌ CGConfigureDisplayMirrorOfDisplay for HiDPI** — on Apple Silicon it triggers hardware mirroring + mouse stutter; ✅ use a plist override (/Library/Displays/)
