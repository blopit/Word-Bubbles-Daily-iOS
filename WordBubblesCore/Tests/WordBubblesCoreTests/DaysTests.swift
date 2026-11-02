import XCTest
@testable import WordBubblesCore

final class DaysTests: XCTestCase {
    private struct GoldenDay: Decodable {
        let year: Int
        let month: Int
        let day: Int
        let number: Int
    }

    private func calendar(_ zone: String, _ identifier: Calendar.Identifier = .gregorian) throws -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    func testPuzzleIndexRotates() {
        XCTAssertEqual(Engine.puzzleIndex(day: 1, count: 100), 0)
        XCTAssertEqual(Engine.puzzleIndex(day: 100, count: 100), 99)
        XCTAssertEqual(Engine.puzzleIndex(day: 101, count: 100), 0)
    }

    func testPuzzleIndexBeforeTheEpoch() {
        XCTAssertEqual(Engine.puzzleIndex(day: 0, count: 100), 99)
        XCTAssertEqual(Engine.puzzleIndex(day: -5, count: 100), 94)
        XCTAssertEqual(Engine.puzzleIndex(day: -100_000, count: 100), 99)
    }

    func testPuzzleIndexWorksForEveryInt() {
        XCTAssertEqual(Engine.puzzleIndex(day: .min, count: 100), 91)
        XCTAssertEqual(Engine.puzzleIndex(day: .max, count: 100), 6)
    }

    func testGoldenDays() throws {
        for zone in ["UTC", "America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let calendar = try calendar(zone)
            for golden in try Golden.load([GoldenDay].self, "days") {
                for hour in [0, 12, 23] {
                    let date = try date(golden.year, golden.month, golden.day, hour: hour, in: calendar)
                    XCTAssertEqual(Engine.dayNumber(for: date, calendar: calendar), golden.number, "\(golden) \(zone) \(hour)h")
                }
            }
        }
    }

    func testTheNumberFollowsTheLocalDateNotUTC() throws {
        let instant = try date(2026, 9, 2, hour: 2, in: calendar("UTC"))
        XCTAssertEqual(Engine.dayNumber(for: instant, calendar: try calendar("UTC")), 2)
        XCTAssertEqual(Engine.dayNumber(for: instant, calendar: try calendar("America/New_York")), 1)
    }

    func testANonGregorianDeviceCalendarGetsTheSameNumber() throws {
        let date = try date(2026, 11, 2, hour: 12, in: calendar("UTC"))
        for identifier in [Calendar.Identifier.buddhist, .japanese, .hebrew, .islamicCivil] {
            XCTAssertEqual(Engine.dayNumber(for: date, calendar: try calendar("UTC", identifier)), 63, "\(identifier)")
        }
    }

    func testDateForDayIsThatLocalCalendarDate() throws {
        for golden in try Golden.load([GoldenDay].self, "days") {
            let calendar = try calendar("America/Los_Angeles")
            let date = Engine.date(forDay: golden.number, calendar: calendar)
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual([parts.year, parts.month, parts.day], [golden.year, golden.month, golden.day])
        }
    }

    func testDateForDayRoundTripsAcrossDaylightSavingChanges() throws {
        // Havana and Santiago change clocks at midnight, so some local midnights do not exist.
        for zone in ["America/Havana", "America/Santiago", "Asia/Beirut", "Pacific/Apia", "Australia/Lord_Howe"] {
            let calendar = try calendar(zone)
            for day in -10...800 {
                XCTAssertEqual(Engine.dayNumber(for: Engine.date(forDay: day, calendar: calendar), calendar: calendar), day, zone)
            }
        }
    }
}
