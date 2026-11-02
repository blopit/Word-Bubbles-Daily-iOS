import XCTest
@testable import WordBubblesCore

final class LevelTests: XCTestCase {
    func testPlayableExcludesTutorialAndKeepsSeedOrder() {
        XCTAssertEqual(Level.playable, [.easy, .medium, .hard])
    }

    func testMetaMatchesWeb() {
        XCTAssertEqual(Level.easy.label, "Easy")
        XCTAssertEqual(Level.medium.label, "Medium")
        XCTAssertEqual(Level.hard.label, "Hard")
        XCTAssertEqual(Level.tutorial.label, "Tutorial")

        XCTAssertEqual(Level.easy.icon, "🟢")
        XCTAssertEqual(Level.medium.icon, "🟡")
        XCTAssertEqual(Level.hard.icon, "🔴")
        XCTAssertEqual(Level.tutorial.icon, "🫧")

        XCTAssertEqual(Level.easy.weights, [1: 0.10, 2: 0.45, 3: 0.45])
        XCTAssertEqual(Level.medium.weights, [1: 0.22, 2: 0.48, 3: 0.30])
        XCTAssertEqual(Level.hard.weights, [1: 0.30, 2: 0.45, 3: 0.25])
        XCTAssertEqual(Level.tutorial.weights, [1: 0, 2: 0.5, 3: 0.5])

        XCTAssertTrue(Level.easy.showLengths)
        XCTAssertFalse(Level.medium.showLengths)
        XCTAssertFalse(Level.hard.showLengths)
        XCTAssertTrue(Level.tutorial.showLengths)
    }

    func testRawValuesMatchWebKeys() {
        XCTAssertEqual(Level.allCases.map(\.rawValue), ["easy", "medium", "hard", "tutorial"])
    }
}
