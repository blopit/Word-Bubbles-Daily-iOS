import XCTest
@testable import WordBubblesCore

final class LevelProgressTests: XCTestCase {
    func testFreshMatchesJS() {
        let p = LevelProgress()
        XCTAssertEqual(p.found, [])
        XCTAssertEqual(p.consumed, [])
        XCTAssertEqual(p.moves, 0)
        XCTAssertEqual(p.hints, [:])
        XCTAssertFalse(p.done)
        XCTAssertEqual(p.points, 0)
        XCTAssertEqual(p.bestCombo, 0)
        XCTAssertEqual(p.bonus, [])
        XCTAssertEqual(p.elapsed, 0)
        XCTAssertFalse(p.usedHint)
        XCTAssertFalse(p.newRecord)
        XCTAssertNil(p.newRegional)
    }

    func testRoundTrip() throws {
        var p = LevelProgress()
        p.found = [1]
        p.consumed = ["1-0", "1-1"]
        p.moves = 4
        p.hints = [2: 1]
        p.points = 90
        p.bestCombo = 2
        p.bonus = ["TOE"]
        p.elapsed = 1234.5
        p.usedHint = true
        p.newRecord = true
        p.newRegional = .country
        let back = try JSONDecoder().decode(LevelProgress.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testMissingOptionalKeysDecodeToDefaults() throws {
        let json = #"{"found":[0],"consumed":["0-0"],"moves":2,"hints":{"1":2},"done":false}"#
        let p = try JSONDecoder().decode(LevelProgress.self, from: Data(json.utf8))
        XCTAssertEqual(p.found, [0])
        XCTAssertEqual(p.hints, [1: 2])
        XCTAssertEqual(p.points, 0)
        XCTAssertEqual(p.bonus, [])
        XCTAssertEqual(p.elapsed, 0)
        XCTAssertNil(p.newRegional)
    }

    func testRecordWithoutFoundArrayIsFresh() throws {
        // recFor: a record whose `found` is not an array is thrown away
        let p = try JSONDecoder().decode(LevelProgress.self, from: Data(#"{"found":"x","moves":9}"#.utf8))
        XCTAssertEqual(p, LevelProgress())
        let q = try JSONDecoder().decode(LevelProgress.self, from: Data(#"{"moves":9}"#.utf8))
        XCTAssertEqual(q, LevelProgress())
    }

    func testOneBadOptionalFieldDoesNotLoseTheRest() throws {
        let p = try JSONDecoder().decode(LevelProgress.self, from: Data(#"{"found":[1],"points":"lots","moves":3}"#.utf8))
        XCTAssertEqual(p.found, [1])
        XCTAssertEqual(p.points, 0)
        XCTAssertEqual(p.moves, 3)
    }

    func testForfeitedMedal() {
        var p = LevelProgress()
        XCTAssertFalse(p.forfeitedMedal)
        p.hints = [0: 0]
        XCTAssertFalse(p.forfeitedMedal)
        p.hints = [0: 1]
        XCTAssertTrue(p.forfeitedMedal)
        p.hints = [:]
        p.usedHint = true
        XCTAssertTrue(p.forfeitedMedal)
    }
}

final class StatsTests: XCTestCase {
    func testDefaults() {
        let s = Stats()
        XCTAssertEqual(s, Stats(days: 0, streak: 0, best: 0, perfect: 0, lastDay: nil))
    }

    func testFirstDayStartsStreak() {
        var s = Stats()
        s.record(day: 10, perfect: false)
        XCTAssertEqual(s, Stats(days: 1, streak: 1, best: 1, perfect: 0, lastDay: 10))
    }

    func testConsecutiveDayExtendsStreak() {
        var s = Stats(days: 3, streak: 3, best: 3, perfect: 1, lastDay: 9)
        s.record(day: 10, perfect: true)
        XCTAssertEqual(s, Stats(days: 4, streak: 4, best: 4, perfect: 2, lastDay: 10))
    }

    func testGapResetsStreakButKeepsBest() {
        var s = Stats(days: 5, streak: 5, best: 5, perfect: 0, lastDay: 8)
        s.record(day: 10, perfect: false)
        XCTAssertEqual(s, Stats(days: 6, streak: 1, best: 5, perfect: 0, lastDay: 10))
    }

    func testSameDayCountsOnce() {
        var s = Stats(days: 1, streak: 1, best: 1, perfect: 1, lastDay: 10)
        s.record(day: 10, perfect: true)
        XCTAssertEqual(s, Stats(days: 1, streak: 1, best: 1, perfect: 1, lastDay: 10))
    }

    func testDecodingTolerance() throws {
        let s = try JSONDecoder().decode(Stats.self, from: Data(#"{"days":2}"#.utf8))
        XCTAssertEqual(s, Stats(days: 2, streak: 0, best: 0, perfect: 0, lastDay: nil))
    }
}

final class ProgressStoreTests: XCTestCase {
    func done() -> LevelProgress {
        var p = LevelProgress()
        p.done = true
        return p
    }

    func testMissingFileGivesEmptyState() {
        let store = ProgressStore(url: tempStoreURL(), today: 50)
        XCTAssertEqual(store.record(day: 50, level: .easy), LevelProgress())
        XCTAssertEqual(store.stats, Stats())
        XCTAssertFalse(store.tutorialDone)
    }

    func testCorruptFileGivesEmptyState() throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let store = ProgressStore(url: url, today: 50)
        XCTAssertFalse(store.isDone(day: 50, level: .easy))
        XCTAssertEqual(store.stats, Stats())
    }

    func testWrongShapeFileGivesEmptyState() throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"[1,2,3]"#.utf8).write(to: url)
        XCTAssertEqual(ProgressStore(url: url, today: 50).stats, Stats())
        try Data(#"{"days":7,"stats":"x"}"#.utf8).write(to: url)
        XCTAssertEqual(ProgressStore(url: url, today: 50).stats, Stats())
    }

    func testOneBadRecordKeepsTheOthers() throws {
        let url = tempStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = #"{"days":{"50":{"easy":{"found":[0],"done":true},"medium":7,"nonsense":{"found":[]}}},"tutorialDone":true}"#
        try Data(json.utf8).write(to: url)
        let store = ProgressStore(url: url, today: 50)
        XCTAssertTrue(store.isDone(day: 50, level: .easy))
        XCTAssertEqual(store.record(day: 50, level: .medium), LevelProgress())
        XCTAssertTrue(store.tutorialDone)
    }

    func testRoundTrip() {
        let url = tempStoreURL()
        let store = ProgressStore(url: url, today: 50)
        var p = LevelProgress()
        p.found = [2]
        p.consumed = ["2-0"]
        p.hints = [1: 1]
        p.elapsed = 500.5
        store.setRecord(p, day: 48, level: .medium)
        store.setStats(Stats(days: 2, streak: 2, best: 4, perfect: 1, lastDay: 49))
        store.setTutorialDone()
        let reopened = ProgressStore(url: url, today: 50)
        XCTAssertEqual(reopened.record(day: 48, level: .medium), p)
        XCTAssertEqual(reopened.stats, Stats(days: 2, streak: 2, best: 4, perfect: 1, lastDay: 49))
        XCTAssertTrue(reopened.tutorialDone)
    }

    func testWriteLeavesNoTempFiles() throws {
        let url = tempStoreURL()
        let store = ProgressStore(url: url, today: 50)
        store.setRecord(done(), day: 50, level: .easy)
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(names, ["progress.json"])
    }

    func testPrunesDaysOlderThanKeepWindow() {
        let url = tempStoreURL()
        let store = ProgressStore(url: url, today: 500)
        store.setRecord(done(), day: 99, level: .easy)
        store.setRecord(done(), day: 100, level: .easy)
        store.setRecord(done(), day: 500, level: .easy)
        let reopened = ProgressStore(url: url, today: 500)
        XCTAssertFalse(reopened.isDone(day: 99, level: .easy))
        XCTAssertTrue(reopened.isDone(day: 100, level: .easy), "today - 400 is kept")
        XCTAssertTrue(reopened.isDone(day: 500, level: .easy))
    }

    func testRolloverMovesTodayAndPrunes() {
        let store = ProgressStore(url: tempStoreURL(), today: 500)
        store.setRecord(done(), day: 100, level: .easy)
        store.rollover(today: 501)
        XCTAssertEqual(store.today, 501)
        XCTAssertFalse(store.isDone(day: 100, level: .easy))
    }

    func testFirstOpenLevel() {
        let store = ProgressStore(url: tempStoreURL(), today: 50)
        XCTAssertEqual(store.firstOpenLevel(day: 50), .easy)
        store.setRecord(done(), day: 50, level: .easy)
        XCTAssertEqual(store.firstOpenLevel(day: 50), .medium)
        store.setRecord(done(), day: 50, level: .hard)
        XCTAssertEqual(store.firstOpenLevel(day: 50), .medium)
        store.setRecord(done(), day: 50, level: .medium)
        XCTAssertEqual(store.firstOpenLevel(day: 50), .hard, "all done falls back to hard")
    }

    func testUnfinishedDay() {
        let store = ProgressStore(url: tempStoreURL(), today: 3)
        XCTAssertEqual(store.unfinishedDay(except: nil), 3)
        XCTAssertEqual(store.unfinishedDay(except: 3), 2)
        for level in Level.playable { store.setRecord(done(), day: 2, level: level) }
        XCTAssertEqual(store.unfinishedDay(except: 3), 1)
        for level in Level.playable { store.setRecord(done(), day: 1, level: level) }
        XCTAssertNil(store.unfinishedDay(except: 3), "never below day 1")
    }

    func testUnfinishedAtLevel() {
        let store = ProgressStore(url: tempStoreURL(), today: 3)
        store.setRecord(done(), day: 3, level: .easy)
        XCTAssertEqual(store.unfinishedAt(level: .easy, except: nil), 2)
        XCTAssertEqual(store.unfinishedAt(level: .medium, except: nil), 3)
        XCTAssertEqual(store.unfinishedAt(level: .medium, except: 3), 2)
        store.setRecord(done(), day: 2, level: .easy)
        store.setRecord(done(), day: 1, level: .easy)
        XCTAssertNil(store.unfinishedAt(level: .easy, except: nil))
    }

    func testSearchStopsAtKeepWindow() {
        let store = ProgressStore(url: tempStoreURL(), today: 1000)
        for day in 600...1000 {
            for level in Level.playable { store.setRecord(done(), day: day, level: level, persist: false) }
        }
        XCTAssertNil(store.unfinishedDay(except: nil))
        XCTAssertNil(store.unfinishedAt(level: .hard, except: nil))
    }

    func testInitialLevelPrefersTutorialOnToday() {
        let store = ProgressStore(url: tempStoreURL(), today: 50)
        XCTAssertEqual(store.initialLevel(day: 50), .tutorial)
        XCTAssertEqual(store.initialLevel(day: 49), .easy)
        store.setTutorialDone()
        XCTAssertEqual(store.initialLevel(day: 50), .easy)
    }

    func testLevelAfterMovingDayStaysOnTheSameDifficulty() {
        let store = ProgressStore(url: tempStoreURL(), today: 50)
        store.setRecord(done(), day: 49, level: .easy)
        XCTAssertEqual(store.level(forDay: 49, stayingOn: .hard), .hard)
        XCTAssertEqual(store.level(forDay: 49, stayingOn: .tutorial), .medium)
    }

    func testTabBadge() {
        let store = ProgressStore(url: tempStoreURL(), today: 50)
        XCTAssertEqual(store.tabBadge(day: 50, level: .easy, wordCount: 3), "")
        var p = LevelProgress()
        p.found = [1]
        store.setRecord(p, day: 50, level: .easy)
        XCTAssertEqual(store.tabBadge(day: 50, level: .easy, wordCount: 3), "1/3")
        store.setRecord(done(), day: 50, level: .easy)
        XCTAssertEqual(store.tabBadge(day: 50, level: .easy, wordCount: 3), "✓")
    }

    func testDayNavigation() {
        let store = ProgressStore(url: tempStoreURL(), today: 50)
        XCTAssertTrue(store.canGoBack(from: 2))
        XCTAssertFalse(store.canGoBack(from: 1))
        XCTAssertFalse(store.canGoForward(from: 50))
        XCTAssertTrue(store.canGoForward(from: 49))
    }

    func testDayRowsNewestFirstWithinWindow() {
        let store = ProgressStore(url: tempStoreURL(), today: 3)
        for level in Level.playable { store.setRecord(done(), day: 2, level: level) }
        store.setRecord(done(), day: 1, level: .medium)
        let rows = store.dayRows()
        XCTAssertEqual(rows.map(\.day), [3, 2, 1])
        XCTAssertEqual(rows[0].done, [])
        XCTAssertEqual(rows[0].buttonLabel, "Play")
        XCTAssertEqual(rows[1].done, Level.playable)
        XCTAssertEqual(rows[1].buttonLabel, "Open")
        XCTAssertEqual(rows[2].done, [.medium])
        XCTAssertEqual(rows[2].buttonLabel, "Play")
        let long = ProgressStore(url: tempStoreURL(), today: 1000)
        XCTAssertEqual(long.dayRows().count, 401)
    }
}
