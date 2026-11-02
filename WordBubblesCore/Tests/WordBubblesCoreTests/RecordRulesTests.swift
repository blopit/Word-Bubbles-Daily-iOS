import XCTest
@testable import WordBubblesCore

final class RecordRulesTests: XCTestCase {
    let a = RecordEntry(ms: 41_200, pts: 120)

    func testBeatsWhenNothingStands() {
        XCTAssertTrue(Records.beats(a, nil))
    }

    func testBeatsComparesWholeSeconds() {
        XCTAssertTrue(Records.beats(RecordEntry(ms: 40_999, pts: 0), a))
        XCTAssertFalse(Records.beats(RecordEntry(ms: 41_000, pts: 120), a), "same second, same points")
        XCTAssertFalse(Records.beats(RecordEntry(ms: 41_999, pts: 100), a), "same second, fewer points")
        XCTAssertTrue(Records.beats(RecordEntry(ms: 41_999, pts: 121), a), "same second, more points")
        XCTAssertFalse(Records.beats(RecordEntry(ms: 42_000, pts: 999), a))
    }

    func testHoldsAllowsATie() {
        XCTAssertFalse(Records.holds(a, nil))
        XCTAssertTrue(Records.holds(RecordEntry(ms: 41_000, pts: 120), a))
        XCTAssertFalse(Records.holds(RecordEntry(ms: 41_000, pts: 119), a))
        XCTAssertTrue(Records.holds(RecordEntry(ms: 40_000, pts: 0), a))
        XCTAssertFalse(Records.holds(RecordEntry(ms: 42_000, pts: 500), a))
    }

    func testPlausibleIs400msPerBubble() {
        XCTAssertTrue(Records.plausible(ms: 4000, bubbleCount: 10))
        XCTAssertFalse(Records.plausible(ms: 3999, bubbleCount: 10))
        XCTAssertFalse(Records.plausible(ms: 3999.6, bubbleCount: 10))
    }
}
