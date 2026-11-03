import WordBubblesCore
import XCTest
@testable import WordBubbles

final class CalendarMonthTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func months(today: Int = 63, rows: [DayRow] = [], firstWeekday: Int = 1) -> [CalendarMonth] {
        CalendarMonth.months(today: today, rows: rows, calendar: calendar(firstWeekday: firstWeekday))
    }

    func testMonthsRunOldestToNewest() {
        XCTAssertEqual(months().map(\.title), ["September 2026", "October 2026", "November 2026"])
    }

    func testBlanksLineTheFirstDayUpWithItsWeekday() {
        // Sep 1 2026 is a Tuesday
        XCTAssertEqual(months()[0].leadingBlanks, 2)
        XCTAssertEqual(months(firstWeekday: 2)[0].leadingBlanks, 1)
    }

    func testEveryDateInTheMonthHasACell() {
        XCTAssertEqual(months()[0].cells.count, 30)
        XCTAssertEqual(months()[1].cells.count, 31)
        XCTAssertEqual(months()[2].cells.count, 30)
    }

    func testCellsCarryTheGameDayNumber() {
        let all = months()
        XCTAssertEqual(all[0].cells[0].day, 1)
        XCTAssertEqual(all[1].cells[0].day, 31)
        XCTAssertEqual(all[2].cells[1].day, 63)
        XCTAssertEqual(all[2].cells[1].date, 2)
    }

    func testDaysAfterTodayCannotBeOpened() {
        let november = months()[2]
        XCTAssertTrue(november.cells[1].isPlayable)
        XCTAssertFalse(november.cells[2].isPlayable)
    }

    func testDaysBeforeTheArchiveCannotBeOpened() {
        // Day 500 keeps 400 days, back to day 100 (Dec 9 2026)
        let all = months(today: 500)
        XCTAssertEqual(all.first?.title, "December 2026")
        XCTAssertFalse(all[0].cells[7].isPlayable)
        XCTAssertTrue(all[0].cells[8].isPlayable)
    }

    func testFinishedLevelsComeFromTheRows() {
        let rows = [DayRow(day: 63, done: [.easy, .hard], buttonLabel: "Play")]
        let cell = months(rows: rows)[2].cells[1]
        XCTAssertEqual(cell.done, [.easy, .hard])
        XCTAssertEqual(months(rows: rows)[2].cells[0].done, [])
    }

    func testWeekdayLettersFollowTheFirstWeekday() {
        XCTAssertEqual(CalendarMonth.weekdays(calendar: calendar()).first, "S")
        XCTAssertEqual(CalendarMonth.weekdays(calendar: calendar(firstWeekday: 2)).first, "M")
        XCTAssertEqual(CalendarMonth.weekdays(calendar: calendar()).count, 7)
    }

    func testADeviceOnAnotherCalendarStillGetsTheRightMonths() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        buddhist.locale = Locale(identifier: "en_US")
        let all = CalendarMonth.months(today: 63, rows: [], calendar: buddhist)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].cells[0].day, 1)
    }
}
