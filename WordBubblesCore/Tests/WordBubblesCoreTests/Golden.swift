import XCTest
@testable import WordBubblesCore

/// Loads the fixtures produced by the real JS engine (scripts/export-web-data.mjs).
enum Golden {
    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name)"
        )
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    /// `[id, text, wi, ci, nudge]`
    struct BubbleRow: Decodable {
        let bubble: Bubble

        init(from decoder: Decoder) throws {
            var row = try decoder.unkeyedContainer()
            bubble = Bubble(
                id: try row.decode(String.self),
                text: try row.decode(String.self),
                wordIndex: try row.decode(Int.self),
                chunkIndex: try row.decode(Int.self),
                nudge: try row.decode(Int.self)
            )
        }
    }

    struct Board: Decodable {
        let day: Int?
        let level: Level
        let theme: String
        let words: [String]
        let chunksByWord: [[String]]
        let bubbles: [BubbleRow]
        let unique: Bool
        let strict: Bool
        let attempts: Int?

        var data: PuzzleData { PuzzleData(theme: theme, words: words) }

        var puzzle: Puzzle {
            Puzzle(
                level: level, theme: theme, words: words, chunksByWord: chunksByWord,
                bubbles: bubbles.map(\.bubble), unique: unique, strict: strict, attempts: attempts
            )
        }
    }

    static func boards() throws -> [Board] { try load([Board].self, "boards") }
}
