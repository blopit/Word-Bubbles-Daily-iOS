import XCTest
@testable import WordBubblesCore

let usFormatter = DayFormatter(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

/// Day 1 easy has 9 bubbles: gold 0:27, silver 0:45, bronze 1:12. Base score 160.
class ResultCardTestCase: XCTestCase {
    let toronto = Place.detect(timeZoneID: "America/Toronto")
    var store = ProgressStore(url: tempStoreURL(), today: 1)

    override func setUp() {
        store = ProgressStore(url: tempStoreURL(), today: 1)
    }

    func put(day: Int = 1, level: Level = .easy, _ change: (inout LevelProgress) -> Void = { _ in }) {
        var p = store.record(day: day, level: level)
        p.done = true
        change(&p)
        store.setRecord(p, day: day, level: level, persist: false)
    }

    func card(
        day: Int = 1, level: Level = .easy, records: [String: RecordEntry]? = nil, place: Place? = nil
    ) -> BoardResult {
        guard case let .board(result) = ResultCard.make(
            day: day, level: level, store: store, place: place ?? toronto, records: records, formatter: usFormatter
        ) else {
            XCTFail("expected a board card")
            fatalError()
        }
        return result
    }
}

final class ResultCardBodyTests: ResultCardTestCase {
    func testTagStarsAndWords() {
        put { $0.points = 330; $0.bestCombo = 3; $0.elapsed = 20_000 }
        let result = card()
        XCTAssertEqual(result.tag, "Sep 1, 2026 · Easy")
        XCTAssertEqual(result.stars, 3)
        XCTAssertEqual(result.pointsLine, "330 points · best combo ×3")
        XCTAssertEqual(result.words, ["TO·AS·T", "B·AC·ON", "CER·EA·L"])
    }

    func testPointsLineWithoutACombo() {
        put { $0.points = 210; $0.bestCombo = 1 }
        XCTAssertEqual(card().pointsLine, "210 points")
    }

    func testBestComboShowsTheCappedMultiplier() {
        put { $0.points = 900; $0.bestCombo = 5 }
        XCTAssertEqual(card().pointsLine, "900 points · best combo ×4")
    }

    func testStarsFloorAtOneOnceFinished() {
        put { $0.points = 10 }
        XCTAssertEqual(card().stars, 1)
    }

    func testBonusWords() {
        put(day: 17, level: .hard) { $0.bonus = ["IRON", "NOT"] }
        XCTAssertEqual(card(day: 17, level: .hard).bonusWords, [
            BonusChip(word: "IRON", isSecret: true), BonusChip(word: "NOT", isSecret: false),
        ])
    }

    func testTutorialCard() {
        guard case let .tutorial(result) = ResultCard.make(
            day: 5, level: .tutorial, store: store, place: toronto, records: nil, formatter: usFormatter
        ) else { return XCTFail("expected the tutorial card") }
        XCTAssertEqual(result.title, "You've got it")
        XCTAssertEqual(result.body, "Bubbles click into place when they make a word. Today's boards hide 3, 4 and 5 words. Every word scores, nothing is ever taken away, and words in a row build a combo.")
        XCTAssertEqual(result.primary, ResultButton(label: "Play today's Easy", icon: .play, action: .play(day: 1, level: .easy)))
    }
}

final class ResultCardMedalTests: ResultCardTestCase {
    func pillTexts(_ result: BoardResult) -> [String] { result.pills.map(\.text) }
    func hit(_ result: BoardResult) -> [String] { result.pills.filter(\.isHit).map(\.key) }

    func testGold() {
        put { $0.elapsed = 20_000 }
        let result = card()
        XCTAssertEqual(result.best, ResultBest(key: "gold", icon: nil, text: "Gold · 0:20"))
        XCTAssertEqual(pillTexts(result), ["0:27", "0:45", "1:12"])
        XCTAssertEqual(hit(result), ["gold"])
        XCTAssertEqual(result.pills[0].accessibilityLabel, "Gold 0:27, yours")
        XCTAssertEqual(result.pills[1].accessibilityLabel, "Silver 0:45")
    }

    func testBoundariesAreInclusive() {
        put { $0.elapsed = 27_000 }
        XCTAssertEqual(card().best.key, "gold")
        put { $0.elapsed = 27_001 }
        XCTAssertEqual(card().best.key, "silver")
        put { $0.elapsed = 45_000 }
        XCTAssertEqual(card().best.key, "silver")
        put { $0.elapsed = 72_000 }
        XCTAssertEqual(card().best.key, "bronze")
        put { $0.elapsed = 72_001 }
        XCTAssertNil(card().best.key)
    }

    func testTheCardRoundsTheTimeFirst() {
        put { $0.elapsed = 27_000.4 }
        XCTAssertEqual(card().best.key, "gold")
    }

    func testNoMedal() {
        put { $0.elapsed = 100_000 }
        let result = card()
        XCTAssertEqual(result.best, ResultBest(key: nil, icon: nil, text: "No medal · 1:40"))
        XCTAssertEqual(hit(result), [])
    }

    func testHintForfeitsMedalAndRecords() {
        put { $0.elapsed = 5_000; $0.usedHint = true; $0.points = 500 }
        let result = card(records: ["d1-easy": RecordEntry(ms: 10_000, pts: 1)])
        XCTAssertEqual(result.best, ResultBest(key: nil, icon: nil, text: "No medal · 0:05"))
        XCTAssertEqual(hit(result), [])
    }

    func testNoTimeRecorded() {
        put()
        let result = card()
        XCTAssertEqual(result.best, ResultBest(key: nil, icon: nil, text: "Time not recorded"))
        XCTAssertEqual(hit(result), [])
    }

    func testNoServerShowsMedalsOnly() {
        put { $0.elapsed = 20_000 }
        XCTAssertEqual(card(records: nil).pills.map(\.key), ["gold", "silver", "bronze"])
    }

    func testAnEmptyDatabaseShowsOneEmptySlot() {
        // every empty slot looks the same, so the de-dup rule folds them into the world slot
        put { $0.elapsed = 20_000 }
        let result = card(records: [:])
        XCTAssertEqual(result.pills.map(\.key), ["record", "gold", "silver", "bronze"])
        XCTAssertEqual(result.pills[0].text, "—")
        XCTAssertTrue(result.pills[0].isEmpty)
        XCTAssertEqual(result.pills[0].icon, "👑")
        XCTAssertEqual(result.pills[0].accessibilityLabel, "World record, none yet")
        XCTAssertEqual(hit(result), ["gold"])
    }

    func testRecordsListBroadestFirst() {
        put { $0.elapsed = 26_000 }
        let result = card(records: [
            "d1-easy": RecordEntry(ms: 10_000, pts: 1),
            "d1-easy-c-CA": RecordEntry(ms: 12_000, pts: 1),
            "d1-easy-z-America~Toronto": RecordEntry(ms: 13_000, pts: 1),
        ])
        XCTAssertEqual(result.pills.map(\.key), ["record", "country", "local", "gold", "silver", "bronze"])
        XCTAssertEqual(result.pills.map(\.icon), ["👑", "🇨🇦", "📍", nil, nil, nil])
        XCTAssertEqual(pillTexts(result), ["0:10", "0:12", "0:13", "0:27", "0:45", "1:12"])
        XCTAssertEqual(result.pills[1].label, "Canada")
        XCTAssertEqual(result.pills[2].label, "ON & QC")
        XCTAssertEqual(result.pills[2].accessibilityLabel, "ON & QC record 0:13")
        XCTAssertEqual(hit(result), ["gold"])
    }

    func testARecordYouHoldBeatsAMedal() {
        put { $0.elapsed = 10_000; $0.points = 300 }
        let result = card(records: [
            "d1-easy": RecordEntry(ms: 10_000, pts: 300),
            "d1-easy-c-CA": RecordEntry(ms: 10_500, pts: 10),
        ])
        XCTAssertEqual(result.best, ResultBest(key: "record", icon: "👑", text: "World record · 0:10"))
        XCTAssertEqual(hit(result), ["record"])
    }

    func testTheBroadestHeldRecordWins() {
        put { $0.elapsed = 12_000; $0.points = 300 }
        let result = card(records: [
            "d1-easy": RecordEntry(ms: 10_000, pts: 300),
            "d1-easy-c-CA": RecordEntry(ms: 12_400, pts: 200),
        ])
        XCTAssertEqual(result.best, ResultBest(key: "country", icon: "🇨🇦", text: "Canada record · 0:12"))
        XCTAssertEqual(hit(result), ["country"])
    }

    func testHoldingNeedsTheScoreOnATiedSecond() {
        put { $0.elapsed = 10_000; $0.points = 299 }
        let result = card(records: ["d1-easy": RecordEntry(ms: 10_000, pts: 300)])
        XCTAssertEqual(result.best.key, "gold")
    }

    func testRepeatedRecordIsFolded() {
        put { $0.elapsed = 26_000 }
        let result = card(records: [
            "d1-easy": RecordEntry(ms: 10_000, pts: 5),
            "d1-easy-c-CA": RecordEntry(ms: 10_000, pts: 5),
            "d1-easy-z-America~Toronto": RecordEntry(ms: 10_000, pts: 6),
        ])
        XCTAssertEqual(result.pills.map(\.key), ["record", "local", "gold", "silver", "bronze"])
    }

    func testNoCountryNoRegionalSlots() {
        put { $0.elapsed = 26_000 }
        let result = card(records: ["d1-easy": RecordEntry(ms: 10_000, pts: 5)], place: .nowhere)
        XCTAssertEqual(result.pills.map(\.key), ["record", "gold", "silver", "bronze"])
    }
}

final class ResultCardTipTests: ResultCardTestCase {
    func tips(_ have: [String]) -> [[TextSegment]] {
        put { $0.bonus = have }
        return card().tips
    }

    func testMissedLongest() {
        XCTAssertEqual(tips([]), [[.plain("Longest bonus word you missed: "), .bold("BLAST")]])
    }

    func testFoundTheLongest() {
        XCTAssertEqual(tips(["BLAST"]), [[
            .plain("You found the longest bonus word, BLAST! Longest bonus word you missed: "), .bold("BLEAT"),
        ]])
    }

    func testTiesBreakAlphabetically() {
        XCTAssertEqual(tips(["BLEAT"]), [[.plain("Longest bonus word you missed: "), .bold("BLAST")]])
    }

    func testFoundEveryBonusWord() {
        let all = ["ACT", "EAT", "LAST", "ONTO", "BEAT", "BLAST", "TON", "BLEAT", "TOT"]
        XCTAssertEqual(tips(all), [[.plain("You found every bonus word!")]])
    }

    func testBoardsWithoutBonusDataHaveNoTips() {
        put(day: 3) { _ in }
        XCTAssertEqual(card(day: 3).tips, [])
        put(day: 250) { _ in }
        XCTAssertEqual(card(day: 250).tips, [])
    }

    func testOneSecretOnARealBoard() {
        put(day: 17, level: .hard) { _ in }
        let missed = card(day: 17, level: .hard).tips
        XCTAssertEqual(missed.count, 2)
        XCTAssertEqual(missed[1], [.plain("Secret word you missed: "), .secret("IRON")])
        put(day: 17, level: .hard) { $0.bonus = ["IRON"] }
        XCTAssertEqual(card(day: 17, level: .hard).tips[1], [.plain("You found the secret word, "), .secret("IRON"), .plain("!")])
    }

    func testSecretSentences() {
        let list = ["AAAAA", "BBBB", "CCC"].map { (key: "x", word: $0) }
        let sentence = { (have: Set<String>, secrets: Set<String>) -> [TextSegment]? in
            let tips = ResultCard.tips(allBonus: list, have: have, isSecret: { secrets.contains($0) })
            return tips.count == 2 ? tips[1] : nil
        }
        let two: Set<String> = ["AAAAA", "BBBB"]
        let three: Set<String> = ["AAAAA", "BBBB", "CCC"]
        XCTAssertNil(sentence([], []))
        XCTAssertEqual(sentence(two, two), [
            .plain("You found every secret word: "), .secret("AAAAA"), .plain(" and "), .secret("BBBB"), .plain("!"),
        ])
        XCTAssertEqual(sentence(three, three), [
            .plain("You found every secret word: "), .secret("AAAAA"), .plain(", "), .secret("BBBB"),
            .plain(" and "), .secret("CCC"), .plain("!"),
        ])
        XCTAssertEqual(sentence(["AAAAA"], two), [
            .plain("You found the secret word, "), .secret("AAAAA"), .plain("! "),
            .plain("Secret word you missed: "), .secret("BBBB"),
        ])
        XCTAssertEqual(sentence(two, three), [
            .plain("You found the secret words "), .secret("AAAAA"), .plain(" and "), .secret("BBBB"), .plain("! "),
            .plain("Secret word you missed: "), .secret("CCC"),
        ])
        XCTAssertEqual(sentence(["AAAAA"], three), [
            .plain("You found the secret word, "), .secret("AAAAA"), .plain("! "),
            .plain("Secret words you missed: "), .secret("BBBB"), .plain(" and "), .secret("CCC"),
        ])
        XCTAssertEqual(sentence([], three), [
            .plain("Secret words you missed: "), .secret("AAAAA"), .plain(", "), .secret("BBBB"), .plain(" and "), .secret("CCC"),
        ])
    }

    func testAWordUnderTwoKeysCountsOnce() {
        let list = [(key: "a", word: "HOTEL"), (key: "b", word: "HOTEL")]
        XCTAssertEqual(ResultCard.tips(allBonus: list, have: ["HOTEL"], isSecret: { _ in true }), [
            [.plain("You found every bonus word!")],
            [.plain("You found the secret word, "), .secret("HOTEL"), .plain("!")],
        ])
    }
}

final class ResultCardSummaryTests: ResultCardTestCase {
    func testNoSummaryUntilAllThreeAreDone() {
        put()
        put(level: .medium)
        let result = card()
        XCTAssertEqual(result.summary, [])
        XCTAssertFalse(result.showsCountdown)
    }

    func testSummaryAndStreakOnToday() {
        put { $0.points = 330 }
        put(level: .medium) { $0.points = 10 }
        put(level: .hard) { $0.points = 2000 }
        store.setStats(Stats(days: 1, streak: 1, best: 1, perfect: 0, lastDay: 1))
        let result = card()
        XCTAssertEqual(result.summary, [
            SummaryRow(label: "Easy", value: "★★★ · 330"),
            SummaryRow(label: "Medium", value: "★☆☆ · 10"),
            SummaryRow(label: "Hard", value: "★★★ · 2000"),
            SummaryRow(label: "Streak", value: "1 day"),
        ])
        XCTAssertTrue(result.showsCountdown)
    }

    func testStreakPlural() {
        for level in Level.playable { put(level: level) }
        store.setStats(Stats(days: 3, streak: 3, best: 3, perfect: 0, lastDay: 1))
        XCTAssertEqual(card().summary.last, SummaryRow(label: "Streak", value: "3 days"))
    }

    func testEarlierDaysHaveNoStreakOrCountdown() {
        store.rollover(today: 2)
        for level in Level.playable { put(level: level) }
        let result = card()
        XCTAssertEqual(result.summary.map(\.label), ["Easy", "Medium", "Hard"])
        XCTAssertFalse(result.showsCountdown)
    }
}

final class ResultCardActionTests: ResultCardTestCase {
    override func setUp() {
        store = ProgressStore(url: tempStoreURL(), today: 3)
    }

    let share = ResultButton(label: "Share", icon: .share, action: .share)

    func testStaysOnTheDifficultyThenOffersTheNextLevel() {
        put(day: 3)
        let result = card(day: 3)
        XCTAssertEqual(result.primary, ResultButton(label: "Play Sep 2 Easy", icon: .next, action: .play(day: 2, level: .easy)))
        XCTAssertEqual(result.secondary, [ResultButton(label: "Medium", icon: .next, action: .switchLevel(.medium)), share])
    }

    func testToday() {
        put(day: 2)
        XCTAssertEqual(card(day: 2).primary, ResultButton(label: "Play Today Easy", icon: .next, action: .play(day: 3, level: .easy)))
    }

    func testNoOtherDayOfThisDifficultyGoesToTheNextLevel() {
        for day in 1...3 { put(day: day) }
        let result = card(day: 3)
        XCTAssertEqual(result.primary, ResultButton(label: "Play Medium", icon: .next, action: .switchLevel(.medium)))
        XCTAssertEqual(result.secondary, [
            ResultButton(label: "Sep 2 Medium", icon: .earlier, action: .play(day: 2, level: .medium)), share,
        ])
    }

    func testAllThreeOtherDifficultyOnly() {
        for day in 1...3 { put(day: day) }
        put(day: 3, level: .medium)
        put(day: 3, level: .hard)
        let result = card(day: 3)
        XCTAssertEqual(result.primary, ResultButton(label: "Play Sep 2 Medium", icon: .earlier, action: .play(day: 2, level: .medium)))
        XCTAssertEqual(result.secondary, [share])
    }

    func testOtherDayDiffersFromSameDay() {
        put(day: 3)
        put(day: 2)
        let result = card(day: 3)
        XCTAssertEqual(result.primary, ResultButton(label: "Play Sep 1 Easy", icon: .next, action: .play(day: 1, level: .easy)))
        XCTAssertEqual(result.secondary, [
            ResultButton(label: "Medium", icon: .next, action: .switchLevel(.medium)),
            ResultButton(label: "Sep 2 Medium", icon: .earlier, action: .play(day: 2, level: .medium)),
            share,
        ])
    }

    func testSameDayWithNothingElseOpenHereHidesTheRepeat() {
        for level in Level.playable { put(day: 3, level: level) }
        let result = card(day: 3)
        XCTAssertEqual(result.primary?.action, .play(day: 2, level: .easy))
        XCTAssertEqual(result.secondary, [share])
    }

    func testEverythingDoneLeavesOnlyShare() {
        store = ProgressStore(url: tempStoreURL(), today: 1)
        for level in Level.playable { put(level: level) }
        let result = card()
        XCTAssertNil(result.primary)
        XCTAssertEqual(result.secondary, [share])
    }
}

final class ShareTextTests: ResultCardTestCase {
    func text(records: [String: RecordEntry] = [:], place: Place? = nil) -> String {
        ShareText.make(day: 1, store: store, place: place ?? toronto, records: records, formatter: usFormatter)
    }

    func testNothingDone() {
        XCTAssertEqual(text(), "Word Bubbles · Sep 1, 2026\n🟢 Easy —\n🟡 Medium —\n🔴 Hard —")
    }

    func testFullLine() {
        put { $0.points = 330; $0.elapsed = 20_000; $0.bestCombo = 3; $0.bonus = ["ACT", "EAT"] }
        XCTAssertEqual(text().components(separatedBy: "\n")[1], "🟢 Easy ★★★ 🥇 330 0:20 · ×3 combo · ✦2")
    }

    func testSecretCount() {
        put(day: 17, level: .hard) { $0.points = 400; $0.bonus = ["IRON", "NOT"] }
        let line = ShareText.make(day: 17, store: store, place: toronto, records: [:], formatter: usFormatter)
            .components(separatedBy: "\n")[3]
        XCTAssertTrue(line.hasSuffix(" · ✦2 · ◆1"), line)
    }

    func testMinimalLine() {
        put { $0.points = 160; $0.bestCombo = 1 }
        XCTAssertEqual(text().components(separatedBy: "\n")[1], "🟢 Easy ★★☆ 160")
    }

    func testComboCapsAtFour() {
        put { $0.points = 500; $0.bestCombo = 5 }
        XCTAssertTrue(text().components(separatedBy: "\n")[1].hasSuffix(" · ×4 combo"))
    }

    func testBadges() {
        let badge = { (change: (inout LevelProgress) -> Void, records: [String: RecordEntry], place: Place?) -> String in
            self.store = ProgressStore(url: tempStoreURL(), today: 1)
            self.put { $0.points = 160; change(&$0) }
            return self.text(records: records, place: place).components(separatedBy: "\n")[1]
        }
        XCTAssertEqual(badge({ $0.usedHint = true; $0.elapsed = 20_000 }, [:], nil), "🟢 Easy ★★☆ no medal 160 0:20")
        XCTAssertEqual(badge({ $0.newRecord = true; $0.elapsed = 20_000 }, [:], nil), "🟢 Easy ★★☆ 👑 160 0:20")
        XCTAssertEqual(badge({ $0.newRegional = .country; $0.elapsed = 20_000 }, [:], nil), "🟢 Easy ★★☆ 🇨🇦 160 0:20")
        XCTAssertEqual(badge({ $0.newRegional = .local; $0.elapsed = 20_000 }, [:], nil), "🟢 Easy ★★☆ 📍 160 0:20")
        XCTAssertEqual(badge({ $0.newRegional = .country; $0.elapsed = 20_000 }, [:], .nowhere), "🟢 Easy ★★☆ 🥇 160 0:20")
        XCTAssertEqual(badge({ $0.newRegional = .local; $0.elapsed = 20_000 }, [:], .nowhere), "🟢 Easy ★★☆ 📍 160 0:20")
        XCTAssertEqual(badge({ $0.elapsed = 30_000 }, [:], nil), "🟢 Easy ★★☆ 🥈 160 0:30")
        XCTAssertEqual(badge({ $0.elapsed = 50_000 }, [:], nil), "🟢 Easy ★★☆ 🥉 160 0:50")
        XCTAssertEqual(badge({ $0.elapsed = 100_000 }, [:], nil), "🟢 Easy ★★☆ 160 1:40")
        XCTAssertEqual(badge({ _ in }, [:], nil), "🟢 Easy ★★☆ 160")
    }

    func testBadgeFromARecordOnTheLadder() {
        store = ProgressStore(url: tempStoreURL(), today: 1)
        put { $0.points = 160; $0.elapsed = 9_000 }
        let records = ["d1-easy": RecordEntry(ms: 10_000, pts: 1), "d1-easy-c-CA": RecordEntry(ms: 11_000, pts: 1)]
        XCTAssertEqual(text(records: records).components(separatedBy: "\n")[1], "🟢 Easy ★★☆ 👑 160 0:09")
        store = ProgressStore(url: tempStoreURL(), today: 1)
        put { $0.points = 160; $0.elapsed = 10_500 }
        XCTAssertEqual(text(records: records).components(separatedBy: "\n")[1], "🟢 Easy ★★☆ 🇨🇦 160 0:11")
    }

    func testShareUsesTheUnroundedTimeSoItCanDisagreeWithTheCard() {
        put { $0.points = 160; $0.elapsed = 27_000.4 }
        XCTAssertEqual(text().components(separatedBy: "\n")[1], "🟢 Easy ★★☆ 🥈 160 0:27")
        XCTAssertEqual(card().best.key, "gold")
    }

    func testRealPlaythrough() {
        let clock = FakeClock()
        for level in Level.playable {
            var s = realSession(day: 1, level: level, clock: clock, store: store)
            clock.advance(ms: 30_000)
            s.solveAll()
        }
        let lines = text().components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "🟢 Easy ★★★ 🥈 330 0:30 · ×3 combo")
    }
}
