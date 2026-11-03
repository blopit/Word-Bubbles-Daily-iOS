import Foundation
import WordBubblesCore

/// A month of the calendar sheet, in game day numbers, so a date can't open a different board from the one it shows.
struct CalendarMonth: Identifiable, Equatable {
    struct Cell: Identifiable, Equatable {
        var id: Int { day }
        let day: Int
        /// The date within the month, from 1.
        let date: Int
        /// False for dates at either end of a month that fall outside the archive.
        let isPlayable: Bool
        let done: [Level]
    }

    var id: Int { cells[0].day }
    let title: String
    /// Empty cells before the 1st, so it lands under its weekday.
    let leadingBlanks: Int
    let cells: [Cell]

    /// Every month from the start of the archive to `today`, oldest first. Always Gregorian, as game days are.
    static func months(today: Int, rows: [DayRow], calendar device: Calendar) -> [CalendarMonth] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = device.timeZone
        calendar.locale = device.locale
        calendar.firstWeekday = device.firstWeekday
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")

        let oldest = max(1, today - ProgressStore.keepDays)
        let done = Dictionary(rows.map { ($0.day, $0.done) }, uniquingKeysWith: { first, _ in first })
        var months: [CalendarMonth] = []
        var firstDay = oldest - calendar.component(.day, from: Engine.date(forDay: oldest, calendar: calendar)) + 1
        while firstDay <= today {
            let date = Engine.date(forDay: firstDay, calendar: calendar)
            let count = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            months.append(CalendarMonth(
                title: formatter.string(from: date),
                leadingBlanks: (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7,
                cells: (0..<count).map { offset in
                    let day = firstDay + offset
                    return Cell(day: day, date: offset + 1, isPlayable: (oldest...today).contains(day), done: done[day] ?? [])
                }
            ))
            firstDay += count
        }
        return months
    }

    /// One letter per weekday, from the calendar's first weekday.
    static func weekdays(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}
