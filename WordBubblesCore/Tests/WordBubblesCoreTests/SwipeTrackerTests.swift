import XCTest
@testable import WordBubblesCore

/// Day 1 easy: TO·AS·T (0-x), B·AC·ON (1-x), CER·EA·L (2-x).
final class SwipeTrackerTests: XCTestCase {
    var session = realSession()
    var swipe = SwipeTracker()

    override func setUp() {
        session = realSession()
        swipe = SwipeTracker()
    }

    @discardableResult
    func down(_ id: String?) -> [GameEvent] { swipe.pointerDown(hit: id, session: &session) }
    @discardableResult
    func move(_ id: String?) -> [GameEvent] { swipe.pointerMove(hit: id, session: &session) }

    func testPressPicksAndStartsAGesture() {
        XCTAssertEqual(down("0-0"), [.picked(id: "0-0", chainLength: 1, combo: 0)])
        XCTAssertTrue(swipe.isActive)
        XCTAssertEqual(session.chain, ["0-0"])
    }

    func testPressOnNothingDoesNothing() {
        XCTAssertEqual(down(nil), [])
        XCTAssertFalse(swipe.isActive)
    }

    func testSlidingPicksEachBubbleOnce() {
        down("0-0")
        move("0-1")
        XCTAssertEqual(session.chain, ["0-0", "0-1"])
        XCTAssertEqual(move("0-1"), [], "still on the same bubble")
        XCTAssertEqual(session.chain, ["0-0", "0-1"])
    }

    func testMoveOffTheBubblesDoesNothing() {
        down("0-0")
        XCTAssertEqual(move(nil), [])
        move("0-1")
        XCTAssertEqual(session.chain, ["0-0", "0-1"])
    }

    func testMoveWithoutAGestureDoesNothing() {
        XCTAssertEqual(move("0-0"), [])
        XCTAssertEqual(session.chain, [])
    }

    func testTappingAChainedBubbleRemovesIt() {
        down("0-0")
        swipe.pointerUp(session: session)
        let events = down("0-0")
        XCTAssertEqual(events, [.unpicked(ids: ["0-0"]), .comboBroken(wasCombo: false)])
        XCTAssertEqual(session.chain, [])
        XCTAssertFalse(swipe.isActive, "a tap on a chained bubble starts no gesture")
        XCTAssertEqual(move("0-1"), [])
    }

    func testSlidingBackOntoThePreviousBubbleUndoesTheLast() {
        down("2-0")
        move("2-1")
        let events = move("2-0")
        XCTAssertEqual(events, [.unpicked(ids: ["2-1"]), .comboBroken(wasCombo: false)])
        XCTAssertEqual(session.chain, ["2-0"])
        XCTAssertTrue(swipe.isActive)
        move("2-1")
        XCTAssertEqual(session.chain, ["2-0", "2-1"], "the undone bubble can be picked again")
    }

    func testUndoCanWalkBackSeveralSteps() {
        down("2-0")
        move("2-1")
        move("1-0")
        move("2-1")
        XCTAssertEqual(session.chain, ["2-0", "2-1"])
        move("2-0")
        XCTAssertEqual(session.chain, ["2-0"])
    }

    func testReenteringAnOlderBubbleIsIgnored() {
        down("2-0")
        move("2-1")
        move("1-0")
        XCTAssertEqual(move("2-0"), [])
        XCTAssertEqual(session.chain, ["2-0", "2-1", "1-0"])
        // `last` stayed on B, so sliding back to EA still undoes B
        move("2-1")
        XCTAssertEqual(session.chain, ["2-0", "2-1"])
    }

    func testBubblesFromAnEarlierGestureAreIgnored() {
        down("2-0")
        swipe.pointerUp(session: session)
        down("2-1")
        XCTAssertEqual(move("2-0"), [], "chained, but not part of this swipe")
        XCTAssertEqual(session.chain, ["2-0", "2-1"])
    }

    func testAPickThatLocksEndsTheGesture() {
        down("0-0")
        move("0-1")
        let events = move("0-2")
        XCTAssertTrue(events.contains(where: \.isLock))
        XCTAssertFalse(swipe.isActive)
        XCTAssertEqual(move("1-0"), [], "the rest of the swipe is dead")
        XCTAssertEqual(session.chain, [])
    }

    func testAPressThatLocksStartsNoGesture() {
        down("0-0")
        move("0-1")
        swipe.pointerUp(session: session)
        down("0-2")
        XCTAssertFalse(swipe.isActive)
        XCTAssertEqual(session.progress.found, [0])
    }

    func testAPickThatCollectsABonusEndsTheGesture() {
        down("1-1")
        move("0-2")
        XCTAssertEqual(session.progress.bonus, ["ACT"])
        XCTAssertFalse(swipe.isActive)
    }

    func testAFoundBonusKeepsTheGestureGoing() {
        down("1-1")
        move("0-2")
        swipe.pointerUp(session: session)
        down("1-1")
        let events = move("0-2")
        XCTAssertEqual(events.last, .bonusAlreadyFound(word: "ACT"))
        XCTAssertTrue(swipe.isActive)
        move("1-2")
        XCTAssertEqual(session.chain, ["1-1", "0-2", "1-2"])
        // sliding back lands on the found bonus again, which doesn't break anything
        XCTAssertEqual(move("0-2"), [.bonusAlreadyFound(word: "ACT")])
        XCTAssertTrue(swipe.isActive)
    }

    func testFinishedBoardIgnoresPresses() {
        session.solveAll()
        XCTAssertEqual(down("0-0"), [])
        XCTAssertFalse(swipe.isActive)
    }

    func testConsumedBubblesIgnored() {
        session.solve(0)
        XCTAssertEqual(down("0-0"), [])
        XCTAssertFalse(swipe.isActive)
        down("1-0")
        XCTAssertEqual(move("0-0"), [])
        XCTAssertEqual(session.chain, ["1-0"])
    }

    func testPointerUpSavesPendingPicks() {
        let url = tempStoreURL()
        let store = ProgressStore(url: url, today: 1)
        session = realSession(store: store)
        down("0-0")
        XCTAssertEqual(ProgressStore(url: url, today: 1).record(day: 1, level: .easy).moves, 0)
        swipe.pointerUp(session: session)
        XCTAssertEqual(ProgressStore(url: url, today: 1).record(day: 1, level: .easy).moves, 1)
        XCTAssertFalse(swipe.isActive)
    }
}
