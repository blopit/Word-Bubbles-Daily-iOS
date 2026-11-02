import XCTest
@testable import WordBubblesCore

final class GameDataTests: XCTestCase {
    private let data = GameData.shared

    func testEveryGoldenBoardThroughTheBundledData() throws {
        for golden in try Golden.boards() {
            let day = try XCTUnwrap(golden.day)
            XCTAssertEqual(data.puzzle(day: day, level: golden.level), golden.puzzle, "day \(day) \(golden.level)")
        }
    }

    /// The fixtures only cover positive days. Expected values come from `WB.buildPuzzle` in node.
    func testDaysOutsideTheFixtures() {
        let cases: [(Int, Level, Int, [(String, Int)])] = [
            (-5, .easy, 1, [("1-3", -2), ("1-1", -1), ("2-0", -4), ("0-1", -4), ("2-1", -2), ("1-0", 2), ("0-0", 4), ("1-2", 1)]),
            (2_147_483_648, .easy, 1, [("2-1", -2), ("0-0", 2), ("1-2", -5), ("0-2", -3), ("1-1", -2), ("2-0", 4), ("0-1", -3), ("1-0", 1), ("2-2", -5)]),
            // Odd day, so day * 1000003 is odd, past 2^53, and must round exactly as a JS double does.
            (9_007_199_257, .hard, 1, [("0-1", -3), ("3-4", -4), ("1-1", -3), ("4-2", 0), ("3-1", 3), ("4-0", 0), ("2-1", 4), ("4-1", 5), ("0-0", -3), ("3-2", 1), ("2-0", -3), ("3-0", 1), ("1-0", 1), ("3-3", -3)]),
        ]
        for (day, level, attempts, bubbles) in cases {
            let puzzle = data.puzzle(day: day, level: level)
            XCTAssertEqual(puzzle.attempts, attempts, "day \(day)")
            XCTAssertEqual(puzzle.bubbles.map(\.id), bubbles.map(\.0), "day \(day)")
            XCTAssertEqual(puzzle.bubbles.map(\.nudge), bubbles.map(\.1), "day \(day)")
        }
        XCTAssertEqual(data.puzzle(day: 0, level: .hard).attempts, 2)
        XCTAssertEqual(data.puzzle(day: -100_000, level: .medium).bubbles.first?.id, "3-1")
        XCTAssertEqual(data.puzzle(day: 5_000_000, level: .hard).attempts, 3)
    }

    func testPuzzleCount() {
        XCTAssertEqual(data.puzzleCount, 100)
    }

    func testTutorial() throws {
        XCTAssertEqual(data.tutorial, try Golden.load(Golden.Board.self, "tutorial").puzzle)
        XCTAssertEqual(data.puzzle(day: 7, level: .tutorial), data.tutorial)
    }

    func testBonusEntriesKeepFileOrder() {
        let entries = data.bonusEntries(day: 1, level: .easy)
        XCTAssertEqual(entries.map(\.key), ["AC|T", "EA|T", "AS|L|T", "ON|TO", "B|EA|T", "AS|B|L|T", "ON|T", "B|EA|L|T", "T|TO"])
        XCTAssertEqual(entries.map(\.word), ["ACT", "EAT", "LAST", "ONTO", "BEAT", "BLAST", "TON", "BLEAT", "TOT"])
    }

    func testNoBonusEntriesPastTheData() {
        XCTAssertTrue(data.bonusEntries(day: 201, level: .easy).isEmpty)
        XCTAssertTrue(data.bonusEntries(day: 0, level: .easy).isEmpty)
        XCTAssertTrue(data.bonusEntries(day: -3, level: .hard).isEmpty)
    }

    func testTheTutorialHasNoBonusEntries() {
        XCTAssertTrue(data.bonusEntries(day: 1, level: .tutorial).isEmpty)
    }

    /// bonus.json has an empty string for these.
    private let boardsWithNoBonus: Set<String> = [
        "3easy", "6easy", "12easy", "61easy", "64medium", "66easy", "77easy", "99easy", "106easy", "124medium",
        "159easy", "166easy", "181easy",
    ]

    /// Proves split parity against the bonus data: a key is a multiset of chunks, so one wrong split on any of
    /// these boards would leave keys that its bubbles cannot form.
    func testEveryBonusKeyCanBeFormedFromThatBoard() {
        var checked = 0
        for day in 1...200 {
            for level in Level.playable {
                let bubbles = data.puzzle(day: day, level: level).bubbles
                let board = Dictionary(bubbles.map { ($0.text, 1) }, uniquingKeysWith: +)
                let entries = data.bonusEntries(day: day, level: level)
                XCTAssertEqual(entries.isEmpty, boardsWithNoBonus.contains("\(day)\(level)"), "day \(day) \(level)")
                for entry in entries {
                    let chunks = entry.key.split(separator: "|").map(String.init)
                    let needed = Dictionary(chunks.map { ($0, 1) }, uniquingKeysWith: +)
                    for (chunk, count) in needed {
                        XCTAssertGreaterThanOrEqual(board[chunk] ?? 0, count, "\(entry.key) on day \(day) \(level)")
                    }
                    XCTAssertEqual(
                        Engine.decompositions(of: entry.word, pool: chunks), [entry.key],
                        "\(entry.word) should spell from \(entry.key)"
                    )
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 17_073, "every entry in bonus.json")
    }

    func testIsSecret() {
        XCTAssertTrue(data.isSecret(word: "GAMMA", theme: "Greek letters"))
        XCTAssertTrue(data.isSecret(word: "HOTEL", theme: "Hotel"))
        XCTAssertFalse(data.isSecret(word: "GAMMA", theme: "Fruit"))
        XCTAssertFalse(data.isSecret(word: "gamma", theme: "Greek letters"))
        XCTAssertFalse(data.isSecret(word: "GAMMA", theme: "No such theme"))
    }

    func testSafeFromManyThreads() {
        let reader = GameData()
        let serial = GameData.shared
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            let day = i % 20 + 1
            let level = Level.playable[i % 3]
            XCTAssertEqual(reader.puzzle(day: day, level: level), serial.puzzle(day: day, level: level))
            XCTAssertEqual(
                reader.bonusEntries(day: day, level: level).map(\.word),
                serial.bonusEntries(day: day, level: level).map(\.word)
            )
            XCTAssertTrue(reader.isSecret(word: "CHESS", theme: "Board games"))
        }
    }
}
