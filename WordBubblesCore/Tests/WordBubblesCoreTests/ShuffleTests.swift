import XCTest
@testable import WordBubblesCore

final class ShuffleTests: XCTestCase {
    private func bubble(_ word: Int, _ chunk: Int) -> Bubble {
        Bubble(id: "\(word)-\(chunk)", text: "X", wordIndex: word, chunkIndex: chunk, nudge: 0)
    }

    func testNoAdjacentPairs() {
        XCTAssertTrue(Engine.noAdjacentPairs([]))
        XCTAssertTrue(Engine.noAdjacentPairs([bubble(0, 0)]))
        XCTAssertFalse(Engine.noAdjacentPairs([bubble(0, 0), bubble(0, 1)]))
        XCTAssertTrue(Engine.noAdjacentPairs([bubble(0, 1), bubble(0, 0)]), "only forward neighbours count")
        XCTAssertTrue(Engine.noAdjacentPairs([bubble(0, 0), bubble(1, 1)]))
        XCTAssertTrue(Engine.noAdjacentPairs([bubble(0, 0), bubble(0, 2)]))
        XCTAssertFalse(Engine.noAdjacentPairs([bubble(1, 0), bubble(0, 0), bubble(0, 1)]))
    }

    func testStrictShuffleStopsAtTheFirstGoodOrder() {
        var rng = ScriptedRandom(0)
        let result = Engine.shuffleBubbles([bubble(0, 0), bubble(0, 1)], rng: &rng)
        XCTAssertEqual(result.list.map(\.id), ["0-1", "0-0"])
        XCTAssertTrue(result.strict)
        XCTAssertEqual(rng.draws, 3, "one swap, then one nudge per bubble")
    }

    func testGivesUpAfterEightyRounds() {
        var rng = ScriptedRandom(0.99)
        let result = Engine.shuffleBubbles([bubble(0, 0), bubble(0, 1)], rng: &rng)
        XCTAssertEqual(result.list.map(\.id), ["0-0", "0-1"])
        XCTAssertFalse(result.strict)
        XCTAssertEqual(rng.draws, 82)
    }

    func testNudgesUseJSRounding() {
        var rng = ScriptedRandom(0, 0.65, 0.35)
        let result = Engine.shuffleBubbles([bubble(0, 0), bubble(0, 1)], rng: &rng)
        XCTAssertEqual(result.list.map(\.nudge), [2, -2], "(0.65 - 0.5) * 10 and (0.35 - 0.5) * 10")
    }

    func testTiesInNudgesRoundUp() {
        var rng = ScriptedRandom(0, 0.25, 0.75)
        let result = Engine.shuffleBubbles([bubble(0, 0), bubble(0, 1)], rng: &rng)
        XCTAssertEqual(result.list.map(\.nudge), [-2, 3], "-2.5 goes to -2, 2.5 goes to 3")
    }

    func testDoesNotDropBubbles() {
        var rng = Mulberry32(seed: 5)
        let input = (0..<20).map { bubble($0 % 4, $0 / 4) }
        let result = Engine.shuffleBubbles(input, rng: &rng)
        XCTAssertEqual(Set(result.list.map(\.id)), Set(input.map(\.id)))
        XCTAssertEqual(result.list.count, input.count)
    }
}
