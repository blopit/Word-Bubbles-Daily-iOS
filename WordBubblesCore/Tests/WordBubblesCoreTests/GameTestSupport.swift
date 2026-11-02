import Foundation
import XCTest
@testable import WordBubblesCore

/// A clock a test moves by hand.
final class FakeClock {
    var date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.date = date
    }

    func advance(ms: Double) {
        date = date.addingTimeInterval(ms / 1000)
    }

    var now: () -> Date { { self.date } }
}

func tempStoreURL(file: StaticString = #filePath) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wb-tests-\(UUID().uuidString)")
        .appendingPathComponent("progress.json")
}

/// A board from literal chunks, so a test can reach branches real boards rarely hit. Bubbles keep word order.
func syntheticBoard(_ chunks: [[String]], level: Level = .easy, theme: String = "Test") -> Puzzle {
    var bubbles: [Bubble] = []
    for (wordIndex, parts) in chunks.enumerated() {
        for (chunkIndex, text) in parts.enumerated() {
            bubbles.append(Bubble(id: "\(wordIndex)-\(chunkIndex)", text: text, wordIndex: wordIndex, chunkIndex: chunkIndex, nudge: 0))
        }
    }
    return Puzzle(
        level: level, theme: theme, words: chunks.map { $0.joined() }, chunksByWord: chunks, bubbles: bubbles,
        unique: true, strict: true, attempts: 1
    )
}

func syntheticSession(
    _ chunks: [[String]], bonus: [(key: String, word: String)] = [], secrets: Set<String> = [],
    day: Int = 50, today: Int = 50, clock: FakeClock = FakeClock(), store: ProgressStore? = nil
) -> GameSession {
    let board = syntheticBoard(chunks)
    return GameSession(
        day: day, level: board.level, puzzle: board, bonus: bonus, isSecret: { secrets.contains($0) },
        store: store ?? ProgressStore(url: tempStoreURL(), today: today), puzzleFor: { _ in board }, now: clock.now
    )
}

func realSession(
    day: Int = 1, level: Level = .easy, today: Int? = nil, clock: FakeClock = FakeClock(), store: ProgressStore? = nil
) -> GameSession {
    GameSession(
        day: day, level: level, store: store ?? ProgressStore(url: tempStoreURL(), today: today ?? day), now: clock.now
    )
}

extension GameSession {
    /// Picks the first unused live bubble with this text.
    @discardableResult
    mutating func tap(_ text: String) -> [GameEvent] {
        guard let bubble = puzzle.bubbles.first(where: {
            $0.text == text && !progress.consumed.contains($0.id) && !chain.contains($0.id)
        }) else {
            XCTFail("no live bubble \(text)")
            return []
        }
        return addToChain(bubble.id)
    }

    @discardableResult
    mutating func tap(_ texts: String...) -> [GameEvent] {
        texts.flatMap { tap($0) as [GameEvent] }
    }

    func id(of text: String) -> String {
        puzzle.bubbles.first { $0.text == text }!.id
    }

    /// Spells a word from its own bubbles. A piece of the word can itself be a bonus word, which empties the tray,
    /// so it starts again; the bonus is then already found and stays out of the way.
    @discardableResult
    mutating func solve(_ wordIndex: Int) -> [GameEvent] {
        var events: [GameEvent] = []
        while !progress.found.contains(wordIndex) {
            for chunkIndex in puzzle.chunksByWord[wordIndex].indices {
                events += addToChain("\(wordIndex)-\(chunkIndex)")
                if chain.isEmpty { break }
            }
        }
        return events
    }

    @discardableResult
    mutating func solveAll() -> [GameEvent] {
        puzzle.words.indices.flatMap { solve($0) }
    }

    /// Solves the words still unfound.
    mutating func solveAll2() {
        for index in puzzle.words.indices where !progress.found.contains(index) { solve(index) }
    }
}

extension GameEvent {
    var isStar: Bool {
        if case .starEarned = self { return true }
        return false
    }

    var isLock: Bool {
        if case .wordLocked = self { return true }
        return false
    }
}
