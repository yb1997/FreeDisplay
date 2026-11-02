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

        #if DEBUG
        // Test hook for the updater (never in Release builds): launch with
        // `-FDTestInstallUpdate` to check and install right away; set FD_UPDATE_TEST_DMG to a
        // file:// URL to install a local DMG instead of the release's.
        if ProcessInfo.processInfo.arguments.contains("-FDTestInstallUpdate") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await UpdateService.shared.checkForUpdates(force: true)
                let override = ProcessInfo.processInfo.environment["FD_UPDATE_TEST_DMG"].flatMap { URL(string: $0) }
                guard let dmg = override ?? UpdateService.shared.updateDMGURL else {
                    print("[UpdateInstaller] test: no DMG URL")
                    return
                }
                await UpdateInstaller.shared.install(from: dmg)
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrightnessKeyService.shared.stop()
        // GammaService already handles CGDisplayRestoreColorSyncSettings via willTerminateNotification observer.
        VirtualDisplayService.shared.destroyAll()
    }
}
