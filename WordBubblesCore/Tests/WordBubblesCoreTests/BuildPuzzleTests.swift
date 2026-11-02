import XCTest
@testable import WordBubblesCore

final class BuildPuzzleTests: XCTestCase {
    func testSeedBaseMatchesUnsignedShift() {
        XCTAssertEqual(Engine.seedBase(level: .easy, day: 1), 1_007_922)
        XCTAssertEqual(Engine.seedBase(level: .easy, day: -5), 4_289_975_200, "negative days wrap")
        XCTAssertEqual(Engine.seedBase(level: .hard, day: 99_999), 1_215_075_946, "large days wrap")
        XCTAssertEqual(Engine.seedBase(level: .tutorial, day: 1), 1_000_003, "indexOf is -1 for the tutorial")
    }

    /// Exact integer maths would give different seeds here. JS multiplies in doubles, and these odd products
    /// are past 2^53, so they round. Expected values come from node.
    func testSeedBaseRoundsLikeADoublePastTwoToTheFiftyThree() {
        XCTAssertEqual(Engine.seedBase(level: .medium, day: 9_007_199_255), 1_252_068_834)
        XCTAssertEqual(Engine.seedBase(level: .hard, day: 9_007_199_257), 1_254_076_760)
        XCTAssertEqual(Engine.seedBase(level: .easy, day: -9_007_199_255), 3_042_922_220)
    }

    func testEveryGoldenBoard() throws {
        let boards = try Golden.boards()
        XCTAssertEqual(boards.count, 648)
        for golden in boards {
            let built = Engine.buildPuzzle(level: golden.level, day: try XCTUnwrap(golden.day), data: golden.data)
            XCTAssertEqual(built, golden.puzzle, "day \(golden.day ?? 0) \(golden.level)")
        }
    }

    /// Expected values come from `WB.buildPuzzle('tutorial', 1, ...)` in node. The UI never does this, but a
    /// level missing from `LEVELS` still has defined behaviour.
    func testTutorialLevelThroughTheNormalBuilder() {
        let data = PuzzleData(theme: "x", words: ["RAINBOW", "CLOUD"])
        let built = Engine.buildPuzzle(level: .tutorial, day: 1, data: data)
        XCTAssertEqual(built.attempts, 1)
        XCTAssertEqual(built.chunksByWord, [["RAI", "NBO", "W"], ["CLO", "UD"]])
        XCTAssertEqual(built.bubbles.map(\.id), ["0-1", "1-1", "0-0", "1-0", "0-2"])
        XCTAssertEqual(built.bubbles.map(\.nudge), [3, 1, 2, -1, 2])
    }

    func testTutorialMatchesGolden() throws {
        let golden = try Golden.load(Golden.Board.self, "tutorial")
        XCTAssertEqual(Engine.buildTutorial(), golden.puzzle)
        XCTAssertNil(Engine.buildTutorial().attempts)
    }
}
