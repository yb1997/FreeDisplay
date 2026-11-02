# Working Habits — FreeDisplay

> Updated: 2026-03-02

## Build and test

- Build command: `cd ~/Desktop/FreeDisplay && xcodebuild -scheme FreeDisplay -configuration Debug build 2>&1 | tail -5`
- After changing project.yml, you must run `xcodegen generate` before building
- The build output is long; just look at the last few lines (`| tail -5`)

## Code style

- Keep SwiftUI views declarative; extract complex logic into a ViewModel/Service
- Annotate every ObservableObject class with @MainActor (resolves Swift 6 concurrency checks)
- The Service layer uses the singleton pattern (`static let shared`), marked `@unchecked Sendable`

## Project management

- xcodegen manages the project; don't edit the .xcodeproj by hand
- Put new files in the matching subdirectory of FreeDisplay/; xcodegen includes them automatically
- After each phase is complete, update the `[x]` markers in the roadmap

## Agent execution quality control

- Instructions to an agent should include **exact code changes** (which line to change and to what), not high-level descriptions
- A passing build ≠ working functionality; runtime behavior must be verified
- Features that involve hardware interaction (DDC, IOKit) are hard for agents to verify and need manual testing to confirm

## Multi-agent optimization workflow (proven in Rounds 3-4)

- **Separate scanning from fixing**: first run 4 scanning agents in parallel (read-only, no changes), collect every issue, then dispatch the fixing agents — the fixing agents have the full context and don't miss related fixes
- **Scans must cover "feature interaction chains"**: don't just scan single files for bugs; cover the full "user action → UI → Service → system API → callback" chain for each feature, because that's the only way to find cross-Service interaction problems
- **Fix P0 first, build once per batch**: don't pile up too many changes before building, or failures are hard to pinpoint
- **0 warnings is the quality floor**: clean up every warning before each round ends

## SwiftUI component development

- Row components that need local state such as hover/loading → extract into a standalone struct (don't use a @ViewBuilder function; @ViewBuilder doesn't support @State)
- Naming convention: reusable row components are `XxxRow` or `XxxRowView`; private structs get the `private` modifier
- Standard hover effect template: `@State private var isHovered = false` + `.background(Color.primary.opacity(isHovered ? 0.06 : 0))` + `.onHover { isHovered = $0 }` + `.animation(.easeInOut(duration: 0.15), value: isHovered)`

## Multi-agent UX polish workflow (proven over 3 rounds)

- **Group by feature area**: assign MenuBar/DetailView/Sliders/FeatureViews to different agents; never let two agents edit the same file
- **Read before changing**: tell agents to "read the whole file first, then make the changes on the list", so they don't change things based on assumptions
- **Build to verify at the end of each round**: after every agent reports back, do a final build check with `xcodebuild`
- **Make the improvement list specific**: instructions to agents must include the target struct name, the @State variable names, and the exact modifier code, not high-level descriptions like "add a hover effect"

## Debugging patterns

- **File-log debugging**: when stdout/stderr aren't visible (e.g. a menu bar app), write a `~/Desktop/xxx_debug.log` file to trace execution; it's more reliable than print/NSLog
- **Reference-implementation verification**: don't guess at private APIs; use known working open-source projects (Chromium, BetterDisplay, node-mac-virtual-display) as the authoritative reference and check property names and call patterns against them

## UX patterns

- **One-click preset pattern**: wrapping a multi-step operation (create a virtual display + set the resolution + arrange) into a single toggle gives the best user experience; applies to any feature where "only the combination of actions makes sense"

## HiDPI development experience

- **The plist override is the only viable HiDPI approach**: write to `/Library/Displays/Contents/Resources/Overrides/`; it needs administrator privileges (NSAppleScript) and takes effect after the display is reconnected
- **Don't set DisplayProductName in the override plist**: it overrides the system display name
- **Getting the native resolution**: use `availableModes.max()`, not `CGDisplayPixelsWide/High` (the latter returns the current resolution)
- **Loading private frameworks**: always use dlopen+dlsym, never @_silgen_name (it causes a linker error)
