import CoreGraphics

/// Where tray tiles sit inside the pill. Computed, not measured, so a flight knows its landing spot the moment a
/// bubble is picked.
enum TrayLayout {
    static let tileHeight = 42.0
    static let minTileWidth = 42.0
    static let padding = 11.0
    static let lockedEndPadding = 3.0
    static let gap = 5.0
    /// Clear of the combo badge and the Clear button.
    static let edgeInset = 54.0
    /// Clear of the letter count too.
    static let countInset = 100.0

    struct Result: Equatable {
        var rects: [CGRect]
        var scale: Double
        var roomForCount: Bool
    }

    static func frames(texts: [String], pillWidth: Double, pillHeight: Double, locked: Bool, measure: (String) -> Double) -> Result {
        guard !texts.isEmpty else { return Result(rects: [], scale: 1, roomForCount: true) }
        var widths = texts.map { max(measure($0) + padding * 2, minTileWidth) }
        if locked {
            widths[0] += lockedEndPadding
            widths[widths.count - 1] += lockedEndPadding
        }
        let gapWidth = locked ? 0 : gap
        let natural = widths.reduce(0, +) + gapWidth * Double(widths.count - 1)
        let room = max(pillWidth - edgeInset * 2, 1)
        let scale = min(1, room / natural)

        var x = (pillWidth - natural * scale) / 2
        let height = tileHeight * scale
        let y = (pillHeight - height) / 2
        var rects: [CGRect] = []
        for width in widths {
            rects.append(CGRect(x: x, y: y, width: width * scale, height: height))
            x += (width + gapWidth) * scale
        }
        return Result(rects: rects, scale: scale, roomForCount: natural * scale <= pillWidth - countInset * 2)
    }
}
