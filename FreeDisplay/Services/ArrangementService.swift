import Foundation
import CoreGraphics

/// Service for reading and setting display positions in the global coordinate space.
/// On macOS, the display whose bounds contain origin (0, 0) is the main display
/// (the one that shows the Dock and menu bar).
@MainActor
class ArrangementService {
    static let shared = ArrangementService()
    private init() {}

    /// Moves the given display to the specified position in the global coordinate space.
    /// The entire Begin→Origin→Complete transaction runs inside `CGHelpers.runWithTimeout`
    /// so `CGCompleteDisplayConfiguration` cannot block indefinitely on WindowServer IPC.
    /// - Returns: true if the configuration was applied successfully.
    @discardableResult
    func setPosition(x: Int, y: Int, for displayID: CGDirectDisplayID) async -> Bool {
        await CGHelpers.runWithTimeout(seconds: 10, fallback: false) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success,
                  let cfg = config else { return false }
            CGConfigureDisplayOrigin(cfg, displayID, Int32(x), Int32(y))
            let result = CGCompleteDisplayConfiguration(cfg, .forSession)
            if result != .success {
                CGCancelDisplayConfiguration(cfg)
                return false
            }
            return true
        }
    }

    /// Moves several displays in ONE configuration transaction, so macOS never sees a
    /// half-moved layout (which it would "fix" by shoving displays around).
    /// - Returns: true if the configuration was applied successfully.
    @discardableResult
    func setOrigins(_ items: [(id: CGDirectDisplayID, x: Int, y: Int)]) async -> Bool {
        guard !items.isEmpty else { return false }
        return await CGHelpers.runWithTimeout(seconds: 10, fallback: false) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success,
                  let cfg = config else { return false }
            for item in items {
                CGConfigureDisplayOrigin(cfg, item.id, Int32(item.x), Int32(item.y))
            }
            let result = CGCompleteDisplayConfiguration(cfg, .forSession)
            if result != .success {
                CGCancelDisplayConfiguration(cfg)
                return false
            }
            return true
        }
    }

    /// Makes the target display the main display by shifting EVERY display by
    /// -target.origin, so the target lands at (0, 0) and the layout keeps its shape.
    /// (Swapping only the target and the old main mirrored a two-display layout and
    /// left a third display behind.) Reads live bounds rather than cached DisplayInfo values.
    /// - Returns: true if the configuration was applied successfully.
    @discardableResult
    func setAsMainDisplay(_ targetID: CGDirectDisplayID) async -> Bool {
        guard CGDisplayIsMain(targetID) == 0 else { return false }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        guard ids.contains(targetID) else { return false }

        let targetOrigin = CGDisplayBounds(targetID).origin
        // A mirror set moves with its primary; configuring its members separately fails.
        let items = ids
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { id -> (id: CGDirectDisplayID, x: Int, y: Int) in
                let origin = CGDisplayBounds(id).origin
                return (id: id, x: Int(origin.x - targetOrigin.x), y: Int(origin.y - targetOrigin.y))
            }
        return await setOrigins(items)
    }
}
