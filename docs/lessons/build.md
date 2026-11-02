# Lessons Learned — Xcode / Build

> Updated: 2026-03-05

## Xcode / Build

- xcodegen doesn't generate Info.plist automatically → you must set `GENERATE_INFOPLIST_FILE: YES` in project.yml
- Calling ScreenCaptureKit (`SCShareableContent.current`) from an `@MainActor` context produces a non-Sendable error (even with `SWIFT_STRICT_CONCURRENCY: minimal` set) → fix: `@preconcurrency import ScreenCaptureKit`
- Under Swift 6 strict concurrency, singletons produce Sendable errors → mark the class `@unchecked Sendable` + set `SWIFT_STRICT_CONCURRENCY: minimal` for the project

## Phase 12 / Wrap-up

- After adding a service/view file you must run `xcodegen generate` to regenerate the xcodeproj; otherwise other files that reference the new type get "cannot find in scope"
- Service files that use `CGDirectDisplayID` need `import CoreGraphics` (`import Foundation` alone isn't enough)
- `NSWorkspace.shared` needs `import AppKit` (Foundation alone isn't enough)
- When an `NSObject` subclass is a singleton, Swift 6 warns that it's non-Sendable → fix by marking it `@unchecked Sendable`
- `SMAppService` (launch at login) is available on macOS 13+ and needs `import ServiceManagement`
