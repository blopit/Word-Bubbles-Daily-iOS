import XCTest
@testable import WordBubblesCore

/// The one deliberate change from the website: spelling a bonus word on the way to a hidden word banks the bonus
/// and leaves the tiles alone, so the player's half-built word survives.
final class InlineBonusTests: XCTestCase {
    private func session(secrets: Set<String> = []) -> GameSession {
        syntheticSession([["BAN", "ANA"], ["KI", "WI"]], bonus: [("BAN|ANA", "XXXX"), ("BAN|KI", "BANKI")], secrets: secrets)
    }

    private func prefixSession(secrets: Set<String> = []) -> GameSession {
        syntheticSession(
            [["BA", "N", "ANA"], ["KI", "WI"]], bonus: [("BA|N", "BAN"), ("KI|WI|BA", "KIWIBA")], secrets: secrets
        )
    }

    func testABonusThatStartsAHiddenWordKeepsTheChain() {
        var s = prefixSession()
        let events = s.tap("BA", "N")
        XCTAssertEqual(s.chain, ["0-0", "0-1"], "the tiles stay in the tray")
        XCTAssertEqual(s.progress.bonus, ["BAN"])
        XCTAssertEqual(s.progress.points, 15)
        XCTAssertEqual(events.last, .bonusInline(word: "BAN", isSecret: false, points: 15))
    }

    func testTheHiddenWordCanThenBeFinishedWithoutRespelling() {
        var s = prefixSession()
        s.tap("BA", "N")
        let events = s.tap("ANA")
        XCTAssertTrue(events.contains(where: \.isLock))
        XCTAssertEqual(s.progress.found, [0])
        XCTAssertEqual(s.chain, [])
    }

    func testAnInlineBonusDoesNotEndASwipe() {
        var s = prefixSession()
        var swipe = SwipeTracker()
        swipe.pointerDown(hit: "0-0", session: &s)
        swipe.pointerMove(hit: "0-1", session: &s)
        XCTAssertTrue(swipe.isActive)
        let events = swipe.pointerMove(hit: "0-2", session: &s)
        XCTAssertTrue(events.contains(where: \.isLock))
        XCTAssertEqual(s.progress.found, [0])
    }

    func testAnInlineBonusLeavesTheComboAlone() {
        var s = prefixSession()
        s.tap("KI", "WI")
        XCTAssertEqual(s.combo, 1)
        s.tap("BA", "N")
        s.tap("ANA")
        XCTAssertEqual(s.combo, 2)
    }

    func testAnInlineSecretScoresAsASecret() {
        var s = prefixSession(secrets: ["BAN"])
        let events = s.tap("BA", "N")
        XCTAssertEqual(s.progress.points, 75)
        XCTAssertEqual(events.last, .bonusInline(word: "BAN", isSecret: true, points: 75))
    }

    func testAnInlineBonusIsSavedAndIsNotOfferedAgain() {
        var s = prefixSession()
        s.tap("BA", "N")
        XCTAssertNil(s.bonusButton)
        XCTAssertEqual(s.bonusBar, [BonusChip(word: "BAN", isSecret: false)])
    }

    func testABonusThatLeadsNowhereStillEmptiesTheTray() {
        var s = session()
        let events = s.tap("BAN", "KI")
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(events.last, .bonusCollected(word: "BANKI", isSecret: false, points: 25, ids: ["0-0", "1-0"]))
    }

    func testAFoundHiddenWordDoesNotCountAsContinuing() {
        var s = syntheticSession([["BA", "NK"], ["KI", "WI"]], bonus: [("BA|NK", "NOPE"), ("KI|BA", "KIBA")])
        s.tap("BA", "NK")
        XCTAssertEqual(s.progress.found, [0])
        let events = s.tap("KI")
        XCTAssertFalse(events.contains(where: \.isLock))
    }

    func testSpellingFoundBonusAgainOnTheWayToAWordJustFlashes() {
        var s = prefixSession()
        s.tap("BA", "N")
        s.clearChain()
        let events = s.tap("BA", "N")
        XCTAssertEqual(events.last, .bonusAlreadyFound(word: "BAN"))
        XCTAssertEqual(s.chain, ["0-0", "0-1"])
        XCTAssertEqual(s.progress.points, 15)
    }

    func testAnInlineBonusHasTheSameFlashAsABonus() {
        XCTAssertEqual(GameEvent.bonusInline(word: "BAN", isSecret: false, points: 15).flash, Flash(text: "✦ Bonus +15", tone: .hint))
        XCTAssertEqual(GameEvent.bonusInline(word: "BAN", isSecret: true, points: 75).flash, Flash(text: "◆ Secret +75", tone: .secret))
    }
}
