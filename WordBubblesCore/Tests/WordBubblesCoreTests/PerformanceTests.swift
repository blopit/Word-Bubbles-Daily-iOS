import XCTest
@testable import WordBubblesCore

final class PerformanceTests: XCTestCase {
    /// The slowest board in the fixtures takes 77 attempts: about 10ms in release and 25ms in this debug build. The
    /// budget leaves room for a loaded machine, and still catches a search that goes exponential.
    func testTheSlowestBoardBuildsInsideTheBudget() throws {
        let slowest = try XCTUnwrap(try Golden.boards().max { ($0.attempts ?? 0) < ($1.attempts ?? 0) })
        let day = try XCTUnwrap(slowest.day)
        var best = Double.infinity
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = Engine.buildPuzzle(level: slowest.level, day: day, data: slowest.data)
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        XCTAssertLessThan(best, 250)
    }
}
