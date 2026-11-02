import XCTest
@testable import WordBubblesCore

final class SplitWordTests: XCTestCase {
    private let easy = Level.easy.weights

    func testPickSizeWalksTheWeights() {
        var low = ScriptedRandom(0.05), mid = ScriptedRandom(0.5), high = ScriptedRandom(0.99)
        XCTAssertEqual(Engine.pickSize(weights: easy, rng: &low, max: 3), 1)
        XCTAssertEqual(Engine.pickSize(weights: easy, rng: &mid, max: 3), 2)
        XCTAssertEqual(Engine.pickSize(weights: easy, rng: &high, max: 3), 3)
    }

    func testPickSizeRescalesToTheCappedTotal() {
        var rng = ScriptedRandom(0.99)
        XCTAssertEqual(Engine.pickSize(weights: easy, rng: &rng, max: 2), 2)
    }

    func testPickSizeWithNoWeightReturnsMaxWithoutDrawing() {
        var rng = ScriptedRandom(0.5)
        XCTAssertEqual(Engine.pickSize(weights: Level.tutorial.weights, rng: &rng, max: 1), 1)
        XCTAssertEqual(rng.draws, 0)
    }

    func testPickSizeDrawOfExactlyZeroPicksOneEvenAtZeroWeight() {
        var rng = ScriptedRandom(0)
        XCTAssertEqual(Engine.pickSize(weights: Level.tutorial.weights, rng: &rng, max: 3), 1)
    }

    func testNeverLeavesAWordAsOneBubble() {
        var rng = ScriptedRandom(0.99)
        XCTAssertEqual(Engine.splitWord("AB", weights: easy, rng: &rng), ["A", "B"])
    }

    func testNoRunsOfSingleLetters() {
        var rng = ScriptedRandom(0.01)
        XCTAssertEqual(Engine.splitWord("ABCD", weights: Level.hard.weights, rng: &rng), ["A", "BC", "D"])
    }

    func testAFinalSingleMayFollowASingle() {
        var rng = ScriptedRandom(0.01)
        XCTAssertEqual(Engine.splitWord("AB", weights: Level.hard.weights, rng: &rng), ["A", "B"])
    }

    func testOneLetterAndEmptyWords() {
        var rng = ScriptedRandom(0.5)
        XCTAssertEqual(Engine.splitWord("A", weights: easy, rng: &rng), ["A"])
        XCTAssertEqual(Engine.splitWord("", weights: easy, rng: &rng), [])
    }

    /// Expected values come from `WB.splitWord` in node.
    func testMatchesJS() {
        let cases: [(String, Level, Int, [String])] = [
            ("RAINBOW", .hard, 42, ["RA", "IN", "BOW"]),
            ("ALTOCUMULUS", .medium, 7, ["A", "LT", "OCU", "MU", "LU", "S"]),
            ("AB", .easy, 1, ["A", "B"]),
            ("A", .easy, 1, ["A"]),
            ("CAT", .hard, 3, ["CA", "T"]),
            ("TEA", .tutorial, 9, ["TE", "A"]),
        ]
        for (word, level, seed, expected) in cases {
            var rng = Mulberry32(seed: seed)
            XCTAssertEqual(Engine.splitWord(word, weights: level.weights, rng: &rng), expected, word)
        }
    }
}
