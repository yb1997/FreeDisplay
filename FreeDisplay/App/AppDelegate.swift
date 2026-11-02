import AppKit
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent duplicate launches: if an instance is already running, exit right away
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if runningApps.count > 1 {
            print("[FreeDisplay] Another instance is already running, exiting.")
            NSApp.terminate(nil)
            return
        }

        // Start intercepting brightness keys to route them to the display under the cursor.
        BrightnessKeyService.shared.start()

        // Create the auto-brightness singleton now so a saved "enabled" setting starts
        // polling at launch, not only once the Auto Brightness section is first shown.
        _ = AutoBrightnessService.shared

        // Wake re-apply (brightness, gamma, resolution) is handled by DisplayManager.
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrightnessKeyService.shared.stop()
        // GammaService already handles CGDisplayRestoreColorSyncSettings via willTerminateNotification observer.
        VirtualDisplayService.shared.destroyAll()
    }
}
