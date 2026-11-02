import Foundation

/// A run of styled text. Secrets are the words shown in the secret color.
public enum TextSegment: Equatable, Sendable {
    case plain(String)
    case bold(String)
    case secret(String)
}

/// Dates for a day number. The locale and time zone are injected so tests are stable.
public struct DayFormatter {
    private let calendar: Calendar
    private let shortFormat: DateFormatter
    private let fullFormat: DateFormatter
    private let weekdayFormat: DateFormatter

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        let make = { (template: String) -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        shortFormat = make("MMMd")
        fullFormat = make("yMMMd")
        weekdayFormat = make("EEE")
    }

    private func date(_ day: Int) -> Date { Engine.date(forDay: day, calendar: calendar) }

    /// `fmtDate`: "Nov 2".
    public func short(day: Int) -> String { shortFormat.string(from: date(day)) }

    /// `fullDate`: "Nov 2, 2026".
    public func full(day: Int) -> String { fullFormat.string(from: date(day)) }

    /// "Mon".
    public func weekday(day: Int) -> String { weekdayFormat.string(from: date(day)) }

    /// `relDay`: "Today", "Yesterday" or the weekday.
    public func relative(day: Int, today: Int) -> String {
        day == today ? "Today" : day == today - 1 ? "Yesterday" : weekday(day: day)
    }

    /// `dayWord`: "Today" or the short date.
    public func dayWord(day: Int, today: Int) -> String {
        day == today ? "Today" : short(day: day)
    }
}

/// All the copy that is not part of a game event.
public enum GameText {
    /// `fmtTime`: M:SS, rounded to the second.
    public static func time(ms: Double) -> String {
        let total = Int(JSMath.round(ms / 1000))
        let seconds = total % 60
        return "\(total / 60):\(seconds < 10 ? "0" : "")\(seconds)"
    }

    /// "9h 05m", or "30m" in the last hour.
    public static func untilMidnight(now: Date, calendar: Calendar = .current) -> String {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let ms = max(0, next.timeIntervalSince(now) * 1000)
        let hours = Int(ms / 3_600_000)
        let minutes = Int(ms.truncatingRemainder(dividingBy: 3_600_000) / 60000)
        return hours > 0 ? "\(hours)h \(minutes < 10 ? "0" : "")\(minutes)m" : "\(minutes)m"
    }

    public static func countdown(now: Date, calendar: Calendar = .current) -> String {
        "New boards in " + untilMidnight(now: now, calendar: calendar)
    }

    public static func letterCount(_ letters: Int) -> String {
        "\(letters) \(letters == 1 ? "letter" : "letters")"
    }

    /// The tray's text while nothing is picked.
    public static func prompt(level: Level) -> String {
        level == .tutorial ? "Tap RA → IN → BOW" : "Tap bubbles in order"
    }

    public enum Help {
        public static let title = "How to play"
        public static let steps: [[TextSegment]] = [
            [.plain("Today's hidden words are cut into bubbles of 1 to 3 letters and scrambled.")],
            [.plain("Tap or swipe the bubbles that belong together, in order. They fly into the tray, and when they make a word they click into place.")],
            [.plain("Every word scores and nothing is ever taken away, so tap freely. More points earn more stars, up to 3, and a quick finish wins a bronze, silver or gold time medal. Using a hint removes that medal and any record: the finish still shows your time, as no medal. Hidden words in a row build a combo (up to ×4); putting a bubble back or using a hint starts it over.")],
            [
                .plain("Spelled a real word that isn't hidden? It's a "), .bold("bonus word"),
                .plain(" and scores too. One that also fits the theme is a "), .bold("secret word"),
                .plain(": it shows up in purple and scores five times a bonus. Find them early: once a hidden word uses its bubbles, they're gone."),
            ],
            [.plain("Stuck? "), .bold("Shuffle"), .plain(" re-deals the bubbles for free.")],
        ]
        public static let demoChunks = ["RA", "IN", "BOW"]
        public static let demoWord = "RAINBOW"
        public static let footnote = "Three boards a day: Easy, Medium and Hard. New words at midnight. Earlier days stay open from the calendar."
        public static let replayTutorial = "Replay tutorial"
        public static let close = "Got it"
    }

    public enum Days {
        public static let title = "Your days"
        public static let statLabels = ["Days", "Streak", "Best", "3★ days"]
        public static let footnote = "Only today counts toward your streak."
    }

    public enum TutorialResult {
        public static let title = "You've got it"
        public static let body = "Bubbles click into place when they make a word. Today's boards hide 3, 4 and 5 words. Every word scores, nothing is ever taken away, and words in a row build a combo."
        public static let button = "Play today's Easy"
    }
}
