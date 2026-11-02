import XCTest
@testable import WordBubblesCore

final class GameSessionHintTests: XCTestCase {
    func testFirstHintRevealsAChunkAndCostsTheMedal() {
        var s = realSession()
        let events = s.hint()
        XCTAssertEqual(events, [.comboBroken(wasCombo: false), .hintRevealed(wordIndex: 0, chunks: ["TO"], firstHint: true)])
        XCTAssertEqual(events.last?.flash, Flash(text: "Starts with TO … · no medal", tone: .hint))
        XCTAssertTrue(s.progress.usedHint)
        XCTAssertEqual(s.progress.hints, [0: 1])
        XCTAssertFalse(s.clean)
    }

    func testSecondHintStaysOnTheWordAndDropsTheSuffix() {
        var s = realSession()
        s.hint()
        let events = s.hint()
        XCTAssertEqual(events.last, .hintRevealed(wordIndex: 0, chunks: ["TO", "AS"], firstHint: false))
        XCTAssertEqual(events.last?.flash, Flash(text: "Starts with TO · AS …", tone: .hint))
    }

    func testAHintBreaksARunningCombo() {
        var s = realSession()
        s.solve(0)
        s.solve(1)
        XCTAssertEqual(s.hint().first, .comboBroken(wasCombo: true))
        XCTAssertEqual(s.combo, 0)
        s.solve(2)
        XCTAssertEqual(s.combo, 1, "hint solved by hand restarts at one")
        XCTAssertEqual(s.progress.points, 150 + 60)
    }

    func testHintGoesToTheHintedWordThenTheFirstUnfound() {
        var s = realSession(level: .hard)
        s.solve(0)
        s.hint()
        XCTAssertEqual(s.progress.hints, [1: 1], "word 0 is found, so word 1 is first")
        s.solve(2)
        s.hint()
        XCTAssertEqual(s.progress.hints, [1: 2], "stays with the hinted word even after another is solved")
        s.solve(1)
        XCTAssertEqual(s.progress.hints, [:], "solving drops the marks")
        s.hint()
        XCTAssertEqual(s.progress.hints, [3: 1])
    }

    func testFullyRevealedWordAutoLocksForFivePerLetter() {
        var s = realSession()
        s.hint()
        s.hint()
        let events = s.hint()
        XCTAssertEqual(events, [
            .comboBroken(wasCombo: false),
            .wordRevealed(wordIndex: 0, word: "TOAST", ids: ["0-0", "0-1", "0-2"], points: 25, firstHint: false),
        ])
        XCTAssertEqual(events.last?.flash, Flash(text: "Revealed: TOAST +25", tone: .hint))
        XCTAssertEqual(s.progress.found, [0])
        XCTAssertEqual(s.progress.consumed, ["0-0", "0-1", "0-2"])
        XCTAssertEqual(s.progress.hints, [:])
        XCTAssertEqual(s.progress.points, 25)
        XCTAssertEqual(s.combo, 0)
        XCTAssertEqual(s.progress.bestCombo, 0)
    }

    func testRevealOnTheVeryFirstHintKeepsTheNoMedalSuffix() {
        var s = syntheticSession([["ABCDEF"], ["GH", "IJ"]])
        let events = s.hint()
        XCTAssertEqual(events.last, .wordRevealed(wordIndex: 0, word: "ABCDEF", ids: ["0-0"], points: 30, firstHint: true))
        XCTAssertEqual(events.last?.flash, Flash(text: "Revealed: ABCDEF +30 · no medal", tone: .hint))
    }

    func testRevealTakesItsBubblesOutOfTheTrayWithoutCheckingTheRest() {
        var s = realSession()
        s.tap("TO", "L")
        s.hint()
        s.hint()
        let events = s.hint()
        XCTAssertEqual(s.chain, ["2-2"])
        XCTAssertFalse(events.contains(.unpicked(ids: ["0-0"])))
    }

    func testRevealFallsBackToASameTextBubble() {
        var s = syntheticSession([["AB", "CD"], ["AB", "EF"], ["GH", "IJ"]])
        // Spell word 0 with word 1's AB
        s.addToChain("1-0")
        s.addToChain("0-1")
        XCTAssertEqual(s.progress.found, [0])
        XCTAssertEqual(s.progress.consumed, ["1-0", "0-1"])
        XCTAssertEqual(s.hintTargets, [:])
        s.hint()
        XCTAssertEqual(s.hintTargets, ["0-0": 1], "word 1's own AB is gone, so its twin is marked")
        let events = s.hint()
        XCTAssertEqual(events.last, .wordRevealed(wordIndex: 1, word: "ABEF", ids: ["0-0", "1-1"], points: 20, firstHint: false))
        XCTAssertEqual(s.progress.consumed, ["1-0", "0-1", "0-0", "1-1"])
    }

    func testHintTargetsNumberThePieces() {
        var s = realSession()
        XCTAssertEqual(s.hintTargets, [:])
        s.hint()
        XCTAssertEqual(s.hintTargets, ["0-0": 1])
        s.hint()
        XCTAssertEqual(s.hintTargets, ["0-0": 1, "0-1": 2])
        s.hint()
        XCTAssertEqual(s.hintTargets, [:])
    }

    func testRevealCanEarnAStarAndFinishTheBoard() {
        var s = realSession()
        for _ in 0..<(3 + 3 + 2) { s.hint() }
        XCTAssertEqual(s.progress.points, 50)
        let events = s.hint()
        XCTAssertEqual(events, [
            .comboBroken(wasCombo: false),
            .starEarned(stars: 1),
            .wordRevealed(wordIndex: 2, word: "CEREAL", ids: ["2-0", "2-1", "2-2"], points: 30, firstHint: false),
            .finished,
        ])
        XCTAssertEqual(s.progress.points, 80)
        XCTAssertTrue(s.progress.done)
    }

    func testAllHintsLandsOnOneStar() {
        var s = syntheticSession([["ABCDEF"]])
        s.hint()
        XCTAssertEqual(s.progress.points, 30)
        XCTAssertEqual(s.rank.stars, 1, "5 per letter is exactly half the base score")
    }

    func testForfeitOutlivesTheHintedWord() {
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var s = realSession(store: store)
        s.hint()
        s.solve(0)
        XCTAssertEqual(s.progress.hints, [:])
        XCTAssertTrue(s.progress.forfeitedMedal)
        XCTAssertTrue(store.record(day: 1, level: .easy).forfeitedMedal)
        s.solve(1)
        s.solve(2)
        XCTAssertTrue(store.record(day: 1, level: .easy).forfeitedMedal)
        XCTAssertNil(s.finishedBoard, "a forfeited board posts no record")
    }

    func testNoHintsOnADoneBoardOrTheTutorial() {
        var s = realSession()
        s.solveAll()
        XCTAssertEqual(s.hint(), [])
        var t = GameSession(day: 1, level: .tutorial, store: ProgressStore(url: tempStoreURL(), today: 1))
        XCTAssertEqual(t.hint(), [])
        XCTAssertFalse(t.progress.usedHint)
    }

    func testHintLeavesThePickedChainAlone() {
        var s = realSession()
        s.tap("L", "B")
        s.hint()
        XCTAssertEqual(s.chain, ["2-2", "1-0"])
    }
}

final class GameSessionTimeTests: XCTestCase {
    func testElapsedCountsToTheFinish() {
        let clock = FakeClock()
        var s = realSession(clock: clock)
        clock.advance(ms: 12_000)
        XCTAssertEqual(s.liveElapsed, 12_000)
        XCTAssertEqual(s.progress.elapsed, 0, "counted quietly until a tick")
        s.solveAll()
        XCTAssertEqual(s.progress.elapsed, 12_000)
        clock.advance(ms: 5_000)
        XCTAssertEqual(s.liveElapsed, 12_000, "the clock stops at the finish")
    }

    func testPauseAndResume() {
        let clock = FakeClock()
        var s = realSession(clock: clock)
        clock.advance(ms: 1_000)
        s.pause()
        XCTAssertEqual(s.progress.elapsed, 1_000)
        clock.advance(ms: 60_000)
        XCTAssertEqual(s.liveElapsed, 1_000, "time in the background doesn't count")
        s.resume()
        clock.advance(ms: 2_000)
        XCTAssertEqual(s.liveElapsed, 3_000)
        s.pause()
        s.pause()
        XCTAssertEqual(s.progress.elapsed, 3_000)
    }

    func testResumeTwiceDoesNotLoseTime() {
        let clock = FakeClock()
        var s = realSession(clock: clock)
        clock.advance(ms: 1_000)
        s.resume()
        XCTAssertEqual(s.liveElapsed, 1_000)
    }

    func testEachTickIsCappedAtTenMinutes() {
        let clock = FakeClock()
        var s = realSession(clock: clock)
        clock.advance(ms: 3_600_000)
        XCTAssertEqual(s.liveElapsed, 600_000)
        s.pause()
        XCTAssertEqual(s.progress.elapsed, 600_000)
        s.resume()
        clock.advance(ms: 1_000)
        s.pause()
        XCTAssertEqual(s.progress.elapsed, 601_000)
    }

    func testResumeOnAFinishedBoardDoesNothing() {
        let clock = FakeClock()
        var s = realSession(clock: clock)
        clock.advance(ms: 1_000)
        s.solveAll()
        s.resume()
        clock.advance(ms: 9_000)
        XCTAssertEqual(s.liveElapsed, 1_000)
        s.pause()
        XCTAssertEqual(s.progress.elapsed, 1_000)
    }

    func testOpeningADoneBoardStartsNoClock() {
        let clock = FakeClock()
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var s = realSession(clock: clock, store: store)
        clock.advance(ms: 1_000)
        s.solveAll()
        let reopened = realSession(clock: clock, store: store)
        clock.advance(ms: 9_000)
        XCTAssertEqual(reopened.liveElapsed, 1_000)
    }

    func testTutorialCountsNoTime() {
        let clock = FakeClock()
        var t = GameSession(day: 1, level: .tutorial, store: ProgressStore(url: tempStoreURL(), today: 1), now: clock.now)
        clock.advance(ms: 5_000)
        XCTAssertEqual(t.liveElapsed, 0)
        XCTAssertNil(t.clock)
        t.pause()
        t.resume()
        clock.advance(ms: 5_000)
        t.solveAll()
        XCTAssertEqual(t.progress.elapsed, 0)
    }

    func testClockFollowsTheBoardAndForfeit() {
        let clock = FakeClock()
        var s = realSession(clock: clock)
        // 9 bubbles: gold 27s
        clock.advance(ms: 9_000)
        XCTAssertEqual(s.clock?.medal?.key, "gold")
        XCTAssertEqual(s.clock?.fractionLeft ?? 0, 2.0 / 3, accuracy: 1e-9)
        clock.advance(ms: 18_001)
        XCTAssertEqual(s.clock?.medal?.key, "silver")
        s.hint()
        XCTAssertNil(s.clock?.medal)
    }

    func testLeaveTicksAndClears() {
        let clock = FakeClock()
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var s = realSession(clock: clock, store: store)
        s.tap("TO")
        clock.advance(ms: 2_000)
        s.leave()
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(store.record(day: 1, level: .easy).elapsed, 2_000)
        XCTAssertEqual(store.record(day: 1, level: .easy).moves, 1)
    }
}

final class GameSessionPersistenceTests: XCTestCase {
    func testMidBoardRoundTrip() {
        let url = tempStoreURL()
        let clock = FakeClock()
        let store = ProgressStore(url: url, today: 1)
        var s = realSession(clock: clock, store: store)
        s.tap("EA", "T")
        s.solve(1)
        s.hint()
        clock.advance(ms: 4_000)
        s.pause()

        let reopenedStore = ProgressStore(url: url, today: 1)
        var back = realSession(clock: clock, store: reopenedStore)
        XCTAssertEqual(back.progress, s.progress)
        XCTAssertEqual(back.progress.found, [1])
        XCTAssertEqual(back.progress.bonus, ["EAT"])
        XCTAssertEqual(back.progress.hints, [0: 1])
        XCTAssertEqual(back.progress.elapsed, 4_000)
        XCTAssertEqual(back.combo, 0, "combo doesn't survive a reopen")
        XCTAssertEqual(back.liveBubbles.count, 6)
        XCTAssertEqual(back.addToChain("1-0"), [], "consumed bubbles stay consumed")
        back.solveAll2()
        XCTAssertTrue(back.progress.done)
    }

    func testPicksFlushOnPauseAndLocksFlushAtOnce() {
        let url = tempStoreURL()
        let store = ProgressStore(url: url, today: 1)
        var s = realSession(store: store)
        s.tap("EA", "T")
        XCTAssertEqual(ProgressStore(url: url, today: 1).record(day: 1, level: .easy).bonus, ["EAT"])
        s.tap("TO")
        XCTAssertEqual(ProgressStore(url: url, today: 1).record(day: 1, level: .easy).moves, 2, "a pick is saved soon, not now")
        s.pause()
        XCTAssertEqual(ProgressStore(url: url, today: 1).record(day: 1, level: .easy).moves, 3)
    }

    func testPauseAfterTheFinishDoesNotOverwriteLaterStoreChanges() {
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var s = realSession(store: store)
        s.solveAll()
        var record = store.record(day: 1, level: .easy)
        record.newRecord = true
        store.setRecord(record, day: 1, level: .easy)
        s.pause()
        s.leave()
        XCTAssertTrue(store.record(day: 1, level: .easy).newRecord)
    }

    func testReplayStartsTheBoardOver() {
        let clock = FakeClock()
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var s = realSession(clock: clock, store: store)
        clock.advance(ms: 1_000)
        s.solveAll()
        s.replay()
        XCTAssertEqual(s.progress, LevelProgress())
        XCTAssertEqual(store.record(day: 1, level: .easy), LevelProgress())
        XCTAssertEqual(s.order, s.puzzle.bubbles.map(\.id))
        XCTAssertEqual(s.combo, 0)
        XCTAssertTrue(s.clean)
        clock.advance(ms: 2_000)
        XCTAssertEqual(s.liveElapsed, 2_000)
    }

    func testReplayMidBoardCarriesTheCurrentTickLikeTheJS() {
        let clock = FakeClock()
        var s = realSession(clock: clock)
        s.tap("TO")
        clock.advance(ms: 1_000)
        s.replay()
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(s.progress.elapsed, 1_000)
    }

    func testReplayedDayStaysCountedOnce() {
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        for level in Level.playable {
            var s = realSession(level: level, store: store)
            s.solveAll()
        }
        XCTAssertEqual(store.stats.days, 1)
        var again = realSession(store: store)
        again.replay()
        again.solveAll()
        XCTAssertEqual(store.stats.days, 1)
        XCTAssertEqual(store.stats.streak, 1)
    }
}

final class GameSessionTutorialTests: XCTestCase {
    func tutorial(_ store: ProgressStore) -> GameSession {
        GameSession(day: 1, level: .tutorial, store: store)
    }

    func testPrompt() {
        XCTAssertEqual(tutorial(ProgressStore(url: tempStoreURL(), today: 1)).prompt, "Tap RA → IN → BOW")
    }

    func testPlayThrough() {
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var t = tutorial(store)
        t.tap("RA", "IN")
        XCTAssertEqual(t.progress.moves, 0, "moves don't count")
        let events = t.tap("BOW")
        XCTAssertEqual(events, [
            .picked(id: "0-2", chainLength: 3, combo: 0),
            .wordLocked(wordIndex: 0, word: "RAINBOW", ids: ["0-0", "0-1", "0-2"], gained: 0, combo: 1, isTutorial: true, completesBoard: true),
            .finished,
        ])
        XCTAssertEqual(t.progress.points, 0, "no points")
        XCTAssertEqual(t.progress.bestCombo, 0)
        XCTAssertTrue(t.progress.done)
        XCTAssertTrue(store.tutorialDone)
        XCTAssertEqual(store.record(day: 1, level: .easy), LevelProgress(), "nothing leaks to the daily boards")
        XCTAssertNil(t.finishedBoard)
    }

    func testWrongOrderCoachesTheTutorial() {
        var t = tutorial(ProgressStore(url: tempStoreURL(), today: 1))
        let events = t.tap("BOW", "RA", "IN")
        XCTAssertEqual(events.last, .nearMiss(isTutorial: true))
        XCTAssertEqual(events.last?.flash, Flash(text: "Right bubbles. Now tap them in order: RA → IN → BOW", tone: .hint))
    }

    func testPutBacksNeverBreakTheCombo() {
        var t = tutorial(ProgressStore(url: tempStoreURL(), today: 1))
        t.tap("RA")
        XCTAssertEqual(t.removeFromChain("0-0"), [.unpicked(ids: ["0-0"])])
        t.tap("RA")
        XCTAssertEqual(t.clearChain(), [.unpicked(ids: ["0-0"])])
        XCTAssertTrue(t.clean)
    }

    func testWordFlashIfAWordEverRemained() {
        let flash = GameEvent.wordLocked(wordIndex: 0, word: "RAINBOW", ids: [], gained: 0, combo: 1, isTutorial: true, completesBoard: false).flash
        XCTAssertEqual(flash, Flash(text: "RAINBOW ✓", tone: .good))
    }

    func testReplayIsFreshAndTouchesNoStore() {
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var t = tutorial(store)
        t.tap("RA", "IN", "BOW")
        t.replay()
        XCTAssertEqual(t.progress, LevelProgress())
        XCTAssertTrue(store.tutorialDone)
        XCTAssertEqual(store.record(day: 1, level: .tutorial), LevelProgress())
    }
}

final class GameSessionStatsTests: XCTestCase {
    func finishDay(_ day: Int, store: ProgressStore) {
        for level in Level.playable {
            var s = realSession(day: day, level: level, store: store)
            s.solveAll()
        }
    }

    func testStatsOnlyWhenAllThreeOfTodayAreDone() {
        let store = ProgressStore(url: tempStoreURL(), today: 5)
        var easy = realSession(day: 5, level: .easy, store: store)
        easy.solveAll()
        XCTAssertEqual(store.stats, Stats())
        var medium = realSession(day: 5, level: .medium, store: store)
        medium.solveAll()
        XCTAssertEqual(store.stats, Stats())
        var hard = realSession(day: 5, level: .hard, store: store)
        hard.solveAll()
        XCTAssertEqual(store.stats.days, 1)
        XCTAssertEqual(store.stats.lastDay, 5)
    }

    func testEarlierDaysNeverCount() {
        let store = ProgressStore(url: tempStoreURL(), today: 5)
        finishDay(4, store: store)
        XCTAssertEqual(store.stats, Stats())
    }

    func testFinishingYesterdayAfterItPassedDoesNotCount() {
        let store = ProgressStore(url: tempStoreURL(), today: 5)
        var easy = realSession(day: 5, level: .easy, store: store)
        easy.solveAll()
        var medium = realSession(day: 5, level: .medium, store: store)
        medium.solveAll()
        store.rollover(today: 6)
        var hard = realSession(day: 5, level: .hard, store: store)
        hard.solveAll()
        XCTAssertEqual(store.stats, Stats())
    }

    func testStreakAcrossDaysWithAGap() {
        let store = ProgressStore(url: tempStoreURL(), today: 5)
        finishDay(5, store: store)
        store.rollover(today: 6)
        finishDay(6, store: store)
        XCTAssertEqual(store.stats.streak, 2)
        XCTAssertEqual(store.stats.best, 2)
        store.rollover(today: 8)
        finishDay(8, store: store)
        XCTAssertEqual(store.stats.streak, 1)
        XCTAssertEqual(store.stats.best, 2)
        XCTAssertEqual(store.stats.days, 3)
    }

    func testPerfectNeedsThreeStarsEverywhere() {
        let store = ProgressStore(url: tempStoreURL(), today: 5)
        finishDay(5, store: store)
        XCTAssertEqual(store.stats.perfect, 1, "a clean run with combos earns 3★ on each board")
        store.rollover(today: 6)
        var easy = realSession(day: 6, level: .easy, store: store)
        for index in easy.puzzle.words.indices {
            easy.hint()
            easy.solve(index)
        }
        XCTAssertLessThan(Scoring.rank(points: easy.progress.points, puzzle: easy.puzzle, finished: true).stars, 3)
        var medium = realSession(day: 6, level: .medium, store: store)
        medium.solveAll()
        var hard = realSession(day: 6, level: .hard, store: store)
        hard.solveAll()
        XCTAssertEqual(store.stats.perfect, 1)
        XCTAssertEqual(store.stats.days, 2)
    }
}
