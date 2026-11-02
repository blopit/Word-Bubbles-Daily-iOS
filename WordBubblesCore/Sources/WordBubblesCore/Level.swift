/// A difficulty. The web game's `META` table lives here as computed properties.
public enum Level: String, CaseIterable, Codable, Hashable, Sendable {
    case easy, medium, hard, tutorial

    /// The levels on a daily board. The position in this list feeds the board seed, so it must not change.
    public static let playable: [Level] = [.easy, .medium, .hard]

    public var label: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .tutorial: return "Tutorial"
        }
    }

    public var icon: String {
        switch self {
        case .easy: return "🟢"
        case .medium: return "🟡"
        case .hard: return "🔴"
        case .tutorial: return "🫧"
        }
    }

    /// How often a bubble gets 1, 2 or 3 letters. Smaller bubbles mean more pieces, so a harder board.
    public var weights: [Int: Double] {
        switch self {
        case .easy: return [1: 0.10, 2: 0.45, 3: 0.45]
        case .medium: return [1: 0.22, 2: 0.48, 3: 0.30]
        case .hard: return [1: 0.30, 2: 0.45, 3: 0.25]
        case .tutorial: return [1: 0, 2: 0.5, 3: 0.5]
        }
    }

    public var showLengths: Bool {
        switch self {
        case .easy, .tutorial: return true
        case .medium, .hard: return false
        }
    }
}
