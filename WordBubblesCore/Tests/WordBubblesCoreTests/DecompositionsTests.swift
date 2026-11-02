import XCTest
@testable import WordBubblesCore

/// Expected values come from `WB.decompositions` in node.
final class DecompositionsTests: XCTestCase {
    func testSingleSpelling() {
        XCTAssertEqual(Engine.decompositions(of: "ABCD", pool: ["AB", "CD"]), ["AB|CD"])
    }

    func testTwoSpellings() {
        XCTAssertEqual(Engine.decompositions(of: "ABCD", pool: ["AB", "CD", "A", "BCD"]), ["A|BCD", "AB|CD"])
    }

    func testRespectsChunkCounts() {
        XCTAssertEqual(Engine.decompositions(of: "ABAB", pool: ["AB"]), [])
        XCTAssertEqual(Engine.decompositions(of: "ABC", pool: ["AB"]), [])
    }

    func testStopsAfterASecondSpelling() {
        let found = Engine.decompositions(of: "ABAB", pool: ["AB", "AB", "A", "B", "A", "B", "ABA"])
        XCTAssertEqual(found, ["A|A|B|B", "A|AB|B"])
    }

    func testEmptyTarget() {
        XCTAssertEqual(Engine.decompositions(of: "", pool: []), [""])
    }
}
