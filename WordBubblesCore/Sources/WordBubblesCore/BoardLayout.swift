import CoreGraphics
import Foundation

/// The honeycomb board geometry, ported from `layoutBoard`, `fitBoardHeight` and `hitTest` in the web UI.
public struct BoardLayout: Equatable, Sendable {
    public let diameter: Double
    public let fontSize: Double
    /// Bubble centers. The nth point belongs to the nth bubble and never moves during a game.
    public let points: [CGPoint]

    /// The height a full-size honeycomb needs, or 0 for a board too small to lay out.
    public static func fitHeight(width: Double, count: Int) -> Double {
        guard count > 0, width >= 40 else { return 0 }
        var best: (cell: Double, neededHeight: Double)?
        for columns in 1...8 {
            let rows = rowCount(count, columns)
            let cell = min(width / (Double(columns) + (rows > 1 ? 0.5 : 0)), 100)
            let neededHeight = (rows > 1 ? Double(rows - 1) * 0.9 * cell : 0) + cell
            if let current = best {
                let bigger = cell > current.cell + 0.5
                let tied = abs(cell - current.cell) <= 0.5
                if bigger || (tied && neededHeight < current.neededHeight) { best = (cell, neededHeight) }
            } else {
                best = (cell, neededHeight)
            }
        }
        return (best!.neededHeight + 12).rounded(.up)
    }

    /// Lays out `count` bubbles, or returns an empty layout for a board too small to use.
    public static func compute(width: Double, height: Double, count: Int) -> BoardLayout {
        guard count > 0, width >= 40, height >= 40 else { return BoardLayout(diameter: 0, fontSize: 0, points: []) }
        var best: (rows: Int, cell: Double)?
        for columns in 1...8 {
            let rows = rowCount(count, columns)
            let cell = min(
                width / (Double(columns) + (rows > 1 ? 0.5 : 0)),
                height / (rows > 1 ? 1 + Double(rows - 1) * 0.9 : 1)
            )
            if best == nil || cell > best!.cell + 0.5 { best = (rows, cell) }
        }
        let rows = best!.rows
        let cell = min(best!.cell, 100)
        let diameter = JSMath.round(cell * 0.86)

        // Spare bubbles go to the rows nearest the middle. Ties keep the upper row first.
        var counts = Array(repeating: count / rows, count: rows)
        let middle = Double(rows - 1) / 2
        let offCenter = { (row: Int) in abs(Double(row) - middle) }
        let ranked = (0..<rows).sorted { (offCenter($0), $0) < (offCenter($1), $1) }
        for i in 0..<(count % rows) { counts[ranked[i]] += 1 }

        let pitchY = rows > 1 ? cell * 0.9 : cell
        let y0 = (height - (Double(rows - 1) * pitchY + cell)) / 2
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for row in 0..<rows {
            let shift = rows > 1 ? (row % 2 == 1 ? cell / 4 : -cell / 4) : 0
            let x0 = (width - Double(counts[row]) * cell) / 2 + shift
            for i in 0..<counts[row] {
                points.append(CGPoint(x: x0 + Double(i) * cell + cell / 2, y: y0 + Double(row) * pitchY + cell / 2))
            }
        }
        return BoardLayout(diameter: diameter, fontSize: min(24, JSMath.round(diameter * 0.32)), points: points)
    }

    /// The id of the nearest bubble not in `consumed`, if it is within 1.15 radii of `point`.
    /// On an exact tie the earlier bubble in `centers` wins.
    public static func hitTest(
        point: CGPoint, centers: [(id: String, center: CGPoint)], radius: Double, consumed: Set<String> = []
    ) -> String? {
        var bestID: String?
        var bestDistance = Double.infinity
        for (id, center) in centers where !consumed.contains(id) {
            let dx = point.x - center.x, dy = point.y - center.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestID = id
            }
        }
        let limit = radius * 1.15
        return bestDistance <= limit * limit ? bestID : nil
    }

    private static func rowCount(_ count: Int, _ columns: Int) -> Int {
        (count + columns - 1) / columns
    }
}
