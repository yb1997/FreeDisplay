# Phase 15: Interaction polish

> Goal: give every action immediate visual feedback so the overall interaction feels lively and smooth

## Task list

- [x] Add loading states and visual feedback to every slow operation
  - Implementation hints:
    1. `DisplayModeListView.swift`: while switching resolution, show a small `ProgressView()` on the clicked row, with the other rows disabled
    2. `ColorProfileView.swift`: show a ProgressView on the matching row while applying an ICC profile
    3. `MirrorView.swift`: show the status while turning mirroring on/off
    4. Unified pattern: create a `LoadingButton` component — after a click it shows a spinner automatically until the async operation completes
    5. Wherever a Service method is async, call it consistently with the `Task { isLoading = true; defer { isLoading = false }; await ... }` pattern
  - Verification: click any switching action → see the loading animation immediately → it disappears when done

- [x] Add a live value readout and haptic feedback to slider interactions
  - Implementation hints:
    1. Show the current percentage next to every Slider (brightness, contrast, gamma, etc.), updating live while dragging
    2. Briefly highlight the value text on release (change its color with `withAnimation(.easeOut(duration: 0.3))`)
    3. Add `.sensoryFeedback(.selection, trigger: value)` to the sliders, or use `NSHapticFeedbackManager` (on a MacBook trackpad)
    4. Use one value display format: `"75%"` rather than `"0.75"` or `"0%"` (the image adjustments currently show 0% because the value really is 0, but the format should be consistent)
  - Verification: drag a slider → the percentage next to it follows live → a subtle animation gives feedback on release

- [x] Add section expand/collapse animations
  - Implementation hints:
    1. In `DisplayDetailView.swift`, wrap every section's expand/collapse state change in `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))`
    2. Give section content an enter/exit animation with `.transition(.opacity.combined(with: .move(edge: .top)))`
    3. Rotate the section header's arrow icon 90°→0° with `.rotationEffect` when expanding (or animate the switch from chevron.right → chevron.down)
    4. Make sure the animations don't hurt performance: collapsed section content should be conditionally rendered with `if expanded { ... }`, not hidden with opacity
  - Verification: click a section header → the content expands/collapses smoothly, and the arrow rotates

- [x] Improve the overall interaction feel of the menu
  - Implementation hints:
    1. Add a hover effect to clickable rows: `.onHover { isHovered = $0 }` + a background color transition `Color.primary.opacity(isHovered ? 0.05 : 0)`
    2. Add a scale animation when a button is clicked: `.scaleEffect(isPressed ? 0.97 : 1.0)` + `.animation(.easeInOut(duration: 0.1))`
    3. Use `Divider().opacity(0.3)` for the dividers between list items to make the visual hierarchy clearer
    4. Check that every Toggle switch has a consistent style and switches state smoothly
  - Verification: hovering over each row fades a highlight in and out → clicking gives a slight scale feedback → the whole thing feels lively

- [x] Fix the @StateObject singleton anti-pattern
  - Implementation hints:
    1. `MenuBarView.swift`: change `@StateObject private var updateService = UpdateService.shared` → `@ObservedObject private var updateService = UpdateService.shared`
    2. Same for `SettingsService.shared`
    3. Check every place a View wraps a shared singleton in `@StateObject`, and change them all to `@ObservedObject`
    4. Use `@StateObject` only for objects the View creates and owns itself (e.g. `@StateObject private var vm = SomeViewModel()`)
  - Verification: builds + opening and closing the menu repeatedly doesn't flicker from duplicate subscriptions

**Phase acceptance**: builds + subjectively smooth and lively: clicks give immediate feedback, sliders drag smoothly, expand/collapse is animated, no stutter
