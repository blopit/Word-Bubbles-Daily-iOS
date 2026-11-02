import CoreGraphics
import Foundation
import Observation
import WordBubblesCore

/// One bubble's look. A class, so a pick redraws that bubble and nothing else on the board.
@MainActor
@Observable
final class BubbleState {
    var point: CGPoint = .zero
    var selected = false
    var popping = false
    var consumed = false
    var hintNumber: Int?

    init(consumed: Bool) {
        self.consumed = consumed
    }
}

struct TrayTile: Identifiable, Equatable {
    let id: String
    let text: String
    /// Inside the pill.
    var frame: CGRect = .zero
    /// Invisible until the flight carrying it lands.
    var landing: Bool
}

/// A slot and whether it is waiting for its word to land.
struct SlotDisplay: Identifiable, Equatable {
    let id: Int
    let slot: WordSlot
    var arriving: Bool
}

struct TabDisplay: Identifiable, Equatable {
    var id: Level { level }
    let level: Level
    let badge: String
}

enum FlightKind: Equatable {
    /// A bubble shrinking into a tray tile, or a tile growing back into a bubble.
    case toTray, toBoard
    case word(LockTone)
}

struct Flight: Identifiable, Equatable {
    let id: Int
    let text: String
    let from: CGRect
    let to: CGRect
    let kind: FlightKind
    let duration: Double
}

struct CelebrationBubble: Identifiable, Equatable {
    let id: Int
    let size: Double
    let start: CGPoint
    let dx: Double
    let dy: Double
    let duration: Double
}

enum Overlay: Equatable {
    case help, days
}

enum SlideDirection: Equatable {
    case left, right
}
