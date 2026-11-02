import SwiftUI

@main
struct FreeDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var displayManager = DisplayManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(displayManager)
                .task {
                    // After a 2-second delay (allows displays to fully initialize),
                    // position any external display above the built-in display.
                    // No-op unless the user turned on `fd.arrangement.externalAbove` (off by default).
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        displayManager.arrangeExternalAboveBuiltin()
                    }
                }
        } label: {
            Image(systemName: "display")
        }
        .menuBarExtraStyle(.window)
    }
}
