import XCTest
@testable import WordBubblesCore

final class ScoringTests: XCTestCase {
    /// TOAST, BACON, CEREAL: 16 letters, so a base score of 160.
    let board = GameData.shared.puzzle(day: 1, level: .easy)
    let toronto = Place.detect(timeZoneID: "America/Toronto")

    func testMultiplierClampsToOneThroughFour() {
        XCTAssertEqual([-1, 0, 1, 2, 3, 4, 5, 99].map(Scoring.multiplier), [1, 1, 1, 2, 3, 4, 4, 4])
    }

    func testMaxPointsIsTenPerLetter() {
        XCTAssertEqual(Scoring.maxPoints(board), 160)
    }

    func testStarThresholds() {
        XCTAssertEqual(Scoring.rank(points: 0, puzzle: board).stars, 0)
        XCTAssertEqual(Scoring.rank(points: 79, puzzle: board).stars, 0)
        XCTAssertEqual(Scoring.rank(points: 80, puzzle: board).stars, 1)
        XCTAssertEqual(Scoring.rank(points: 159, puzzle: board).stars, 1)
        XCTAssertEqual(Scoring.rank(points: 160, puzzle: board).stars, 2)
        XCTAssertEqual(Scoring.rank(points: 239, puzzle: board).stars, 2)
        XCTAssertEqual(Scoring.rank(points: 240, puzzle: board).stars, 3)
        XCTAssertEqual(Scoring.rank(points: 9999, puzzle: board).stars, 3)
    }

    func testFinishedFloorsToOneStar() {
        XCTAssertEqual(Scoring.rank(points: 10, puzzle: board, finished: false).stars, 0)
        XCTAssertEqual(Scoring.rank(points: 10, puzzle: board, finished: true).stars, 1)
        XCTAssertEqual(Scoring.rank(points: 200, puzzle: board, finished: true).stars, 2)
    }

    func testToNextAndFraction() {
        let zero = Scoring.rank(points: 40, puzzle: board)
        XCTAssertEqual(zero.fraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(zero.toNext, 0.5, accuracy: 1e-9)
        XCTAssertEqual(Scoring.rank(points: 80, puzzle: board).toNext, 0, accuracy: 1e-9)
        XCTAssertEqual(Scoring.rank(points: 120, puzzle: board).toNext, 0.5, accuracy: 1e-9)
        XCTAssertEqual(Scoring.rank(points: 200, puzzle: board).toNext, 0.5, accuracy: 1e-9)
        XCTAssertEqual(Scoring.rank(points: 240, puzzle: board).toNext, 1)
        XCTAssertEqual(Scoring.rank(points: 999, puzzle: board).toNext, 1)
    }

    func testStarText() {
        XCTAssertEqual(Scoring.starText(0), "☆☆☆")
        XCTAssertEqual(Scoring.starText(2), "★★☆")
        XCTAssertEqual(Scoring.starText(3), "★★★")
    }

    func testHeat() {
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 9].map(Scoring.heat), [0, 0, 1, 2, 2, 3, 3])
    }

    func testMedalTimesScaleWithBubbles() {
        let times = Scoring.medalTimes(bubbleCount: 10)
        XCTAssertEqual(times.map(\.key), ["gold", "silver", "bronze"])
        XCTAssertEqual(times.map(\.name), ["Gold", "Silver", "Bronze"])
        XCTAssertEqual(times.map(\.ms), [30_000, 50_000, 80_000])
        XCTAssertEqual(times.map(\.emoji), ["🥇", "🥈", "🥉"])
        XCTAssertEqual(times.map(\.icon), [nil, nil, nil])
    }

    private func entries(world: Int? = nil, country: Int? = nil, local: Int? = nil) -> [String: RecordEntry] {
        var out: [String: RecordEntry] = [:]
        if let world { out["d1-easy"] = RecordEntry(ms: world, pts: 0) }
        if let country { out["d1-easy-c-CA"] = RecordEntry(ms: country, pts: 0) }
        if let local { out["d1-easy-z-America~Toronto"] = RecordEntry(ms: local, pts: 0) }
        return out
    }

    private func ladder(_ records: [String: RecordEntry]) -> [Medal] {
        Scoring.medalLadder(day: 1, level: .easy, bubbleCount: 10, records: records, place: toronto)
    }

    func testLadderWithoutRecordsIsTheMedals() {
        XCTAssertEqual(ladder([:]).map(\.key), ["gold", "silver", "bronze"])
    }

    func testRecordsFasterThanGoldSitAboveIt() {
        let list = ladder(entries(world: 10_000, country: 20_000, local: 25_000))
        XCTAssertEqual(list.map(\.key), ["record", "country", "local", "gold", "silver", "bronze"])
        XCTAssertEqual(list[0].name, "World record")
        XCTAssertEqual(list[0].emoji, "👑")
        XCTAssertEqual(list[0].icon, "👑")
        XCTAssertEqual(list[1].name, "Canada record")
        XCTAssertEqual(list[1].emoji, "🇨🇦")
        XCTAssertEqual(list[2].name, "ON & QC record")
        XCTAssertEqual(list[2].emoji, "📍")
    }

    func testARecordAtOrSlowerThanGoldIsLeftOut() {
        XCTAssertEqual(ladder(entries(world: 30_000)).map(\.key), ["gold", "silver", "bronze"])
        XCTAssertEqual(ladder(entries(world: 29_999)).map(\.key), ["record", "gold", "silver", "bronze"])
    }

    func testANarrowerRecordOnlyShowsWhenSlowerThanTheOneAboveIt() {
        XCTAssertEqual(ladder(entries(world: 10_000, country: 10_000)).map(\.key), ["record", "gold", "silver", "bronze"])
        XCTAssertEqual(ladder(entries(world: 10_000, country: 9_000)).map(\.key), ["record", "gold", "silver", "bronze"])
        XCTAssertEqual(
            ladder(entries(world: 10_000, country: 20_000, local: 15_000)).map(\.key),
            ["record", "country", "gold", "silver", "bronze"]
        )
        XCTAssertEqual(ladder(entries(world: 40_000, country: 20_000)).map(\.key), ["country", "gold", "silver", "bronze"])
    }

    func testPlaceWithoutCountryIgnoresRegionalTiers() {
        let list = Scoring.medalLadder(
            day: 1, level: .easy, bubbleCount: 10, records: entries(world: 10_000, country: 20_000), place: .nowhere
        )
        XCTAssertEqual(list.map(\.key), ["record", "gold", "silver", "bronze"])
    }

    func testMedalBoundariesAreInclusive() {
        var p = LevelProgress()
        let medal = { (ms: Double) in
            Scoring.medalFor(ms: ms, day: 1, level: .easy, bubbleCount: 10, progress: p, records: [:], place: .nowhere)?.key
        }
        XCTAssertEqual(medal(1), "gold")
        XCTAssertEqual(medal(30_000), "gold")
        XCTAssertEqual(medal(30_000.5), "silver")
        XCTAssertEqual(medal(50_000), "silver")
        XCTAssertEqual(medal(50_001), "bronze")
        XCTAssertEqual(medal(80_000), "bronze")
        XCTAssertNil(medal(80_001))
        XCTAssertNil(medal(0), "no time, no medal")
        p.usedHint = true
        XCTAssertNil(medal(1), "a hint forfeits it")
    }

    func testMedalForSeesRecordsInTheLadder() {
        let p = LevelProgress()
        let medal = Scoring.medalFor(
            ms: 10_000, day: 1, level: .easy, bubbleCount: 10, progress: p, records: entries(world: 10_000), place: toronto
        )
        XCTAssertEqual(medal?.emoji, "👑")
    }

    func testClockWindows() {
        let run = { (ms: Double) in Scoring.clock(elapsedMs: ms, forfeited: false, bubbleCount: 10) }
        let start = run(0)
        XCTAssertEqual(start.medal?.key, "gold")
        XCTAssertEqual(start.fractionLeft, 1)
        XCTAssertEqual(start.timeText, "0:00")
        XCTAssertEqual(start.accessibilityLabel, "Gold, 0:30 left, 0:00")
        let half = run(15_000)
        XCTAssertEqual(half.fractionLeft, 0.5)
        let edge = run(30_000)
        XCTAssertEqual(edge.medal?.key, "gold")
        XCTAssertEqual(edge.fractionLeft, 0)
        let silver = run(40_000)
        XCTAssertEqual(silver.medal?.key, "silver")
        XCTAssertEqual(silver.fractionLeft, 0.5)
        XCTAssertEqual(silver.accessibilityLabel, "Silver, 0:10 left, 0:40")
        let bronze = run(65_000)
        XCTAssertEqual(bronze.medal?.key, "bronze")
        XCTAssertEqual(bronze.fractionLeft, 0.5)
        let none = run(80_001)
        XCTAssertNil(none.medal)
        XCTAssertEqual(none.fractionLeft, 0)
        XCTAssertEqual(none.accessibilityLabel, "No medal, 1:20")
    }

    func testClockAfterAHintShowsNoMedal() {
        let clock = Scoring.clock(elapsedMs: 1000, forfeited: true, bubbleCount: 10)
        XCTAssertNil(clock.medal)
        XCTAssertEqual(clock.fractionLeft, 0)
    }
}

final class GameTextTests: XCTestCase {
    let utc = DayFormatter(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

    func testTimeRoundsToSeconds() {
        XCTAssertEqual(GameText.time(ms: 0), "0:00")
        XCTAssertEqual(GameText.time(ms: 499), "0:00")
        XCTAssertEqual(GameText.time(ms: 500), "0:01")
        XCTAssertEqual(GameText.time(ms: 9_000), "0:09")
        XCTAssertEqual(GameText.time(ms: 59_499), "0:59")
        XCTAssertEqual(GameText.time(ms: 59_500), "1:00")
        XCTAssertEqual(GameText.time(ms: 125_000), "2:05")
        XCTAssertEqual(GameText.time(ms: 3_600_000), "60:00")
    }

    func testDayTextOnDayOneAndToday() {
        XCTAssertEqual(utc.short(day: 1), "Sep 1")
        XCTAssertEqual(utc.full(day: 1), "Sep 1, 2026")
        XCTAssertEqual(utc.short(day: 63), "Nov 2")
        XCTAssertEqual(utc.full(day: 63), "Nov 2, 2026")
        XCTAssertEqual(utc.weekday(day: 63), "Mon")
    }

    func testLocaleIsInjected() {
        let british = DayFormatter(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(british.short(day: 63), "2 Nov")
        XCTAssertEqual(british.full(day: 63), "2 Nov 2026")
    }

    func testEveryTimeZoneShowsTheSameDate() {
        for zone in ["Pacific/Auckland", "America/Los_Angeles", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let formatter = DayFormatter(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: zone)!)
            XCTAssertEqual(formatter.full(day: 63), "Nov 2, 2026", zone)
        }
    }

    func testRelativeDay() {
        XCTAssertEqual(utc.relative(day: 63, today: 63), "Today")
        XCTAssertEqual(utc.relative(day: 62, today: 63), "Yesterday")
        XCTAssertEqual(utc.relative(day: 61, today: 63), "Sat")
    }

    func testDayWord() {
        XCTAssertEqual(utc.dayWord(day: 63, today: 63), "Today")
        XCTAssertEqual(utc.dayWord(day: 62, today: 63), "Nov 1")
    }

    private func date(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: h, minute: m, second: s))!
    }

    func testUntilMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(GameText.untilMidnight(now: date(14, 5, 30), calendar: calendar), "9h 54m")
        XCTAssertEqual(GameText.untilMidnight(now: date(0, 0), calendar: calendar), "24h 00m")
        XCTAssertEqual(GameText.untilMidnight(now: date(14, 55), calendar: calendar), "9h 05m")
        XCTAssertEqual(GameText.untilMidnight(now: date(23, 0), calendar: calendar), "1h 00m")
        XCTAssertEqual(GameText.untilMidnight(now: date(23, 30), calendar: calendar), "30m")
        XCTAssertEqual(GameText.untilMidnight(now: date(23, 59, 30), calendar: calendar), "0m")
    }

    func testUntilMidnightOnAClockChangeDay() {
        // Nov 1 2026 is a 25-hour day in New York
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        XCTAssertEqual(GameText.untilMidnight(now: start, calendar: calendar), "25h 00m")
    }

    func testCountdownSentence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(GameText.countdown(now: date(23, 30), calendar: calendar), "New boards in 30m")
    }

    func testLetterCount() {
        XCTAssertEqual(GameText.letterCount(0), "0 letters")
        XCTAssertEqual(GameText.letterCount(1), "1 letter")
        XCTAssertEqual(GameText.letterCount(7), "7 letters")
    }

    func testPrompts() {
        XCTAssertEqual(GameText.prompt(level: .tutorial), "Tap RA → IN → BOW")
        XCTAssertEqual(GameText.prompt(level: .hard), "Tap bubbles in order")
    }

    func testHelpCopyIsVerbatim() {
        XCTAssertEqual(GameText.Help.title, "How to play")
        XCTAssertEqual(GameText.Help.steps.count, 5)
        XCTAssertEqual(GameText.Help.steps[0], [.plain("Today's hidden words are cut into bubbles of 1 to 3 letters and scrambled.")])
        XCTAssertEqual(GameText.Help.steps[1], [.plain("Tap or swipe the bubbles that belong together, in order. They fly into the tray, and when they make a word they click into place.")])
        XCTAssertEqual(GameText.Help.steps[2], [.plain("Every word scores and nothing is ever taken away, so tap freely. More points earn more stars, up to 3, and a quick finish wins a bronze, silver or gold time medal. Using a hint removes that medal and any record: the finish still shows your time, as no medal. Hidden words in a row build a combo (up to ×4); putting a bubble back or using a hint starts it over.")])
        XCTAssertEqual(GameText.Help.steps[3], [
            .plain("Spelled a real word that isn't hidden? It's a "), .bold("bonus word"),
            .plain(" and scores too. One that also fits the theme is a "), .bold("secret word"),
            .plain(": it shows up in purple and scores five times a bonus. Find them early: once a hidden word uses its bubbles, they're gone."),
        ])
        XCTAssertEqual(GameText.Help.steps[4], [.plain("Stuck? "), .bold("Shuffle"), .plain(" re-deals the bubbles for free.")])
        XCTAssertEqual(GameText.Help.footnote, "Three boards a day: Easy, Medium and Hard. New words at midnight. Earlier days stay open from the calendar.")
        XCTAssertEqual(GameText.Help.demoChunks, ["RA", "IN", "BOW"])
        XCTAssertEqual(GameText.Help.demoWord, "RAINBOW")
        XCTAssertEqual(GameText.Help.replayTutorial, "Replay tutorial")
        XCTAssertEqual(GameText.Help.close, "Got it")
    }

    func testDaysCardCopy() {
        XCTAssertEqual(GameText.Days.title, "Your days")
        XCTAssertEqual(GameText.Days.statLabels, ["Days", "Streak", "Best", "3★ days"])
        XCTAssertEqual(GameText.Days.footnote, "Only today counts toward your streak.")
    }

    func testTutorialResultCopy() {
        XCTAssertEqual(GameText.TutorialResult.title, "You've got it")
        XCTAssertEqual(GameText.TutorialResult.body, "Bubbles click into place when they make a word. Today's boards hide 3, 4 and 5 words. Every word scores, nothing is ever taken away, and words in a row build a combo.")
        XCTAssertEqual(GameText.TutorialResult.button, "Play today's Easy")
    }
}
