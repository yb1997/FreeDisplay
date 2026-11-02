import Foundation
import CoreGraphics

/// Represents a single display mode (resolution + refresh rate + HiDPI flag).
struct DisplayMode: Identifiable, Equatable {
    /// Unique identifier: IODisplayModeID
    let id: Int32
    /// Logical width in points
    let width: Int
    /// Logical height in points
    let height: Int
    /// Physical pixel width (HiDPI: 2× logical)
    let pixelWidth: Int
    /// Physical pixel height
    let pixelHeight: Int
    /// Refresh rate in Hz (0 means display default, shown as 60)
    let refreshRate: Double
    /// Whether this is a HiDPI (Retina) scaled mode
    let isHiDPI: Bool
    /// Raw IODisplayModeID for CGConfigureDisplayWithDisplayMode (same as id)
    var ioDisplayModeID: Int32 { id }

    // MARK: - Display strings

    var resolutionString: String {
        "\(width)×\(height)"
    }

    var refreshRateString: String {
        guard refreshRate > 0 else { return "-- Hz" }
        // Round fractional rates to nearest integer: 59.97 → "60Hz", 119.88 → "120Hz"
        return "\(Int(refreshRate.rounded()))Hz"
    }

    // MARK: - Enumeration helpers

    private init(_ mode: CGDisplayMode) {
        id = mode.ioDisplayModeID
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
        isHiDPI = mode.pixelWidth > mode.width
    }

    /// Returns all display modes for the given display, sorted by logical width descending.
    /// Pass `includeHiDPI: true` (default) to include all scaled modes.
    static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              !rawModes.isEmpty else {
            return []
        }

        var seen = Set<Int32>()
        return rawModes.compactMap { mode -> DisplayMode? in
            let modeID = mode.ioDisplayModeID
            guard seen.insert(modeID).inserted else { return nil }  // deduplicate
            guard mode.isUsableForDesktopGUI() else { return nil }
            return DisplayMode(mode)
        }
        .sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
            return false
        }
    }

    /// Returns the current active display mode. Cheap: doesn't enumerate all modes.
    static func currentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        CGDisplayCopyDisplayMode(displayID).map(DisplayMode.init)
    }
}
