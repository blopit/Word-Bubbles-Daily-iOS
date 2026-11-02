import XCTest
@testable import WordBubblesCore

final class PerformanceTests: XCTestCase {
    /// The slowest board in the fixtures takes 77 attempts. Best of five, so a busy machine cannot fail it.
    func testTheSlowestBoardBuildsInsideTheBudget() throws {
        let slowest = try XCTUnwrap(try Golden.boards().max { ($0.attempts ?? 0) < ($1.attempts ?? 0) })
        let day = try XCTUnwrap(slowest.day)
        var best = Double.infinity
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = Engine.buildPuzzle(level: slowest.level, day: day, data: slowest.data)
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        XCTAssertLessThan(best, 50)
    }
}
