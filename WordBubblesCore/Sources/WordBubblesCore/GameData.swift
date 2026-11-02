import Foundation

/// The bundled game data. Each file is decoded once, on first use, and built boards are cached.
/// Safe to call from any thread.
public final class GameData: @unchecked Sendable {
    public static let shared = GameData()

    private struct BoardKey: Hashable {
        let day: Int
        let level: Level
    }

    private let lock = NSLock()
    private var puzzleList: [[String: PuzzleData]]?
    private var bonus: [String: [String: String]]?
    private var secrets: [String: [String]]?
    private var boards: [BoardKey: Puzzle] = [:]

    public init() {}

    /// How many puzzles there are before the rotation repeats.
    public var puzzleCount: Int {
        lock.withLock { loadedPuzzles().count }
    }

    /// The hand-built first board.
    public var tutorial: Puzzle { Engine.buildTutorial() }

    /// The board for a day. The tutorial has no daily board, so `.tutorial` returns `tutorial` for any day.
    public func puzzle(day: Int, level: Level) -> Puzzle {
        guard level != .tutorial else { return tutorial }
        return lock.withLock {
            let key = BoardKey(day: day, level: level)
            if let board = boards[key] { return board }
            let puzzles = loadedPuzzles()
            let entry = puzzles[Engine.puzzleIndex(day: day, count: puzzles.count)]
            guard let data = entry[level.rawValue] else { preconditionFailure("puzzles.json has no \(level) entry") }
            let board = Engine.buildPuzzle(level: level, day: day, data: data)
            boards[key] = board
            return board
        }
    }

    /// The day's bonus words in file order, each with its key: the word's chunks, sorted and joined by "|".
    /// Empty for the tutorial and for days with no bonus data.
    public func bonusEntries(day: Int, level: Level) -> [(key: String, word: String)] {
        guard let letter = level.rawValue.first else { return [] }
        let raw: String? = lock.withLock {
            if bonus == nil { bonus = Self.decode("bonus") }
            return bonus?[String(day)]?[String(letter)]
        }
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: "=", maxSplits: 1)
            return parts.count == 2 ? (key: String(parts[0]), word: String(parts[1])) : nil
        }
    }

    /// A secret is a bonus word that fits the board's theme and is not one of the hidden words.
    public func isSecret(word: String, theme: String) -> Bool {
        lock.withLock {
            if secrets == nil { secrets = Self.decode("secrets") }
            return secrets?[theme]?.contains(word) ?? false
        }
    }

    /// Call with `lock` held.
    private func loadedPuzzles() -> [[String: PuzzleData]] {
        if let puzzleList { return puzzleList }
        let decoded: [[String: PuzzleData]] = Self.decode("puzzles")
        puzzleList = decoded
        return decoded
    }

    private static func decode<T: Decodable>(_ name: String) -> T {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(T.self, from: data)
        else { preconditionFailure("Bundled \(name).json is missing or malformed") }
        return value
    }
}
