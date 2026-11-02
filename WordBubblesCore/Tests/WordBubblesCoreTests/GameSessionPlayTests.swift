import XCTest
@testable import WordBubblesCore

/// Day 1 easy is TO·AS·T, B·AC·ON, CER·EA·L.
final class GameSessionPlayTests: XCTestCase {
    func testOpensWithAnEmptyChainAndTheBoardOrder() {
        let s = realSession()
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(s.order, s.puzzle.bubbles.map(\.id))
        XCTAssertEqual(s.combo, 0)
        XCTAssertTrue(s.clean)
        XCTAssertEqual(s.progress, LevelProgress())
    }

    func testPickAddsToChainAndCountsAMove() {
        var s = realSession()
        let events = s.addToChain("0-0")
        XCTAssertEqual(events, [.picked(id: "0-0", chainLength: 1, combo: 0)])
        XCTAssertEqual(s.chain, ["0-0"])
        XCTAssertEqual(s.progress.moves, 1)
    }

    func testPickRejectsChainedConsumedAndUnknownBubbles() {
        var s = realSession()
        s.addToChain("0-0")
        XCTAssertEqual(s.addToChain("0-0"), [])
        XCTAssertEqual(s.addToChain("nope"), [])
        s.addToChain("0-1")
        s.addToChain("0-2")
        XCTAssertEqual(s.chain, [], "TOAST locked")
        XCTAssertEqual(s.addToChain("0-0"), [])
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(s.progress.moves, 3)
    }

    func testLockingAWord() {
        var s = realSession()
        s.solve(0)
        XCTAssertEqual(s.progress.found, [0])
        XCTAssertEqual(s.progress.consumed, ["0-0", "0-1", "0-2"])
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(s.progress.points, 50)
        XCTAssertEqual(s.combo, 1)
        XCTAssertTrue(s.clean)
        XCTAssertEqual(s.progress.bestCombo, 1)
    }

    func testLockEventCarriesItsFlash() {
        var s = realSession()
        s.tap("TO", "AS")
        let events = s.tap("T")
        XCTAssertEqual(events, [
            .picked(id: "0-2", chainLength: 3, combo: 0),
            .wordLocked(wordIndex: 0, word: "TOAST", ids: ["0-0", "0-1", "0-2"], gained: 50, combo: 1, isTutorial: false, completesBoard: false),
        ])
        XCTAssertEqual(events[1].flash, Flash(text: "TOAST +50", tone: .good))
    }

    func testComboGrowsPointsAndFlash() {
        var s = realSession()
        s.solve(0)
        let events = s.solve(1)
        XCTAssertEqual(s.combo, 2)
        XCTAssertEqual(s.progress.points, 50 + 100)
        XCTAssertEqual(events.compactMap(\.flash).last, Flash(text: "BACON +100 · combo ×2!", tone: .good))
        s.solve(2)
        XCTAssertEqual(s.progress.points, 150 + 180)
        XCTAssertEqual(s.progress.bestCombo, 3)
    }

    func testMultiplierCapsAtFourButComboKeepsCounting() {
        // Day 1 hard: POKER BRIDGE RUMMY SOLITAIRE BLACKJACK = 5,6,5,9,9
        var s = realSession(level: .hard)
        s.solveAll()
        XCTAssertEqual(s.combo, 5)
        XCTAssertEqual(s.progress.bestCombo, 5)
        XCTAssertEqual(s.progress.points, 50 + 120 + 150 + 360 + 360)
    }

    func testPutBackBreaksTheCombo() {
        var s = realSession()
        s.solve(0)
        s.solve(1)
        XCTAssertEqual(s.combo, 2)
        s.tap("CER", "EA")
        let events = s.removeFromChain("2-1")
        XCTAssertEqual(events, [.unpicked(ids: ["2-1"]), .comboBroken(wasCombo: true)])
        XCTAssertEqual(s.chain, ["2-0"])
        XCTAssertEqual(s.combo, 0)
        XCTAssertFalse(s.clean)
        s.tap("EA", "L")
        XCTAssertEqual(s.combo, 1, "a broken run restarts at one")
        XCTAssertTrue(s.clean, "the lock cleans the slate")
        XCTAssertEqual(s.progress.points, 150 + 60)
        XCTAssertEqual(s.progress.bestCombo, 2)
    }

    func testBreakWithSmallComboIsNotARealBreak() {
        var s = realSession()
        s.solve(0)
        s.tap("B")
        XCTAssertEqual(s.removeFromChain("1-0"), [.unpicked(ids: ["1-0"]), .comboBroken(wasCombo: false)])
        s.solve(1)
        XCTAssertEqual(s.combo, 1, "combo 1 was still broken")
        XCTAssertEqual(s.progress.points, 50 + 50)
    }

    func testRemovingABubbleNotInTheChainDoesNothing() {
        var s = realSession()
        s.solve(0)
        s.tap("B")
        XCTAssertEqual(s.removeFromChain("2-1"), [])
        XCTAssertEqual(s.combo, 1)
        XCTAssertEqual(s.chain, ["1-0"])
    }

    func testClearChainBreaksTheCombo() {
        var s = realSession()
        s.solve(0)
        s.solve(1)
        s.tap("CER", "EA")
        let events = s.clearChain()
        XCTAssertEqual(events, [.unpicked(ids: ["2-0", "2-1"]), .comboBroken(wasCombo: true)])
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(s.combo, 0)
    }

    func testClearChainWhenEmptyDoesNothing() {
        var s = realSession()
        s.solve(0)
        XCTAssertEqual(s.clearChain(), [])
        XCTAssertEqual(s.combo, 1)
        XCTAssertTrue(s.clean)
    }

    func testPutBackThatCompletesAWordKeepsTheCombo() {
        var s = realSession()
        s.solve(1)
        s.tap("TO", "AS", "L", "T")
        XCTAssertEqual(s.chain.count, 4)
        let events = s.removeFromChain("2-2")
        XCTAssertEqual(events.filter(\.isLock).count, 1)
        XCTAssertFalse(events.contains(.comboBroken(wasCombo: false)))
        XCTAssertEqual(s.progress.found, [1, 0])
        XCTAssertEqual(s.combo, 2)
    }

    func testPutBackThatMakesANewBonusCollectsIt() {
        var s = realSession()
        s.solve(2)
        s.tap("AC", "ON", "T")
        // ACONT; putting ON back spells ACT
        let events = s.removeFromChain("1-2")
        XCTAssertEqual(events, [.bonusCollected(word: "ACT", isSecret: false, points: 15, ids: ["1-1", "0-2"])])
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(s.combo, 1)
    }

    func testPutBackThatMakesAFoundBonusDoesNotBreakAnything() {
        var s = realSession()
        s.solve(2)
        s.tap("AC", "T")
        s.tap("AC", "ON", "T")
        let events = s.removeFromChain("1-2")
        XCTAssertEqual(events, [.bonusAlreadyFound(word: "ACT")])
        XCTAssertEqual(s.chain, ["1-1", "0-2"])
        XCTAssertEqual(s.combo, 1)
        XCTAssertTrue(s.clean)
    }

    func testPutBackIntoANearMissStillBreaks() {
        var s = realSession()
        s.tap("AS", "TO", "T", "L")
        let events = s.removeFromChain("2-2")
        XCTAssertEqual(events, [.nearMiss(isTutorial: false), .unpicked(ids: ["2-2"]), .comboBroken(wasCombo: false)])
    }

    func testChainDoesNotMatchAFoundWordTwice() {
        let store = ProgressStore(url: tempStoreURL(), today: 50)
        var s = syntheticSession([["AB", "CD"], ["AB", "CD"], ["XY", "ZW"]], store: store)
        s.tap("AB", "CD")
        XCTAssertEqual(s.progress.found, [0])
        s.tap("AB", "CD")
        XCTAssertEqual(s.progress.found, [0, 1], "the spelling goes to the next unfound word")
    }

    func testStarsAreEarnedOnceAndOrderedBeforeTheWordFlash() {
        var s = realSession()
        XCTAssertFalse(s.solve(0).contains { if case .starEarned = $0 { true } else { false } })
        let second = s.solve(1)
        XCTAssertEqual(second.filter(\.isStar), [.starEarned(stars: 1)])
        XCTAssertEqual(second.filter(\.isStar).first?.flash, Flash(text: "You earned a star!", tone: .good))
        XCTAssertLessThan(second.firstIndex(where: \.isStar)!, second.firstIndex(where: \.isLock)!, "the word's flash lands last")
        let third = s.solve(2)
        XCTAssertEqual(third.filter(\.isStar), [.starEarned(stars: 3)])
        XCTAssertEqual(third.filter(\.isStar).first?.flash, Flash(text: "3 stars!", tone: .good))
    }

    func testReopeningABoardDoesNotReAwardItsStars() {
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var first = realSession(store: store)
        first.solve(0)
        first.solve(1)
        var second = realSession(store: store)
        XCTAssertFalse(second.solve(2).contains(where: { $0 == .starEarned(stars: 1) }))
        XCTAssertEqual(second.combo, 1, "the combo resets on reopen")
    }

    func testLastWordFlashesNothingAndFinishes() {
        var s = realSession()
        s.solve(0)
        s.solve(1)
        let events = s.solve(2)
        XCTAssertEqual(events.last, .finished)
        let lock = events.first(where: \.isLock)!
        XCTAssertEqual(lock, .wordLocked(wordIndex: 2, word: "CEREAL", ids: ["2-0", "2-1", "2-2"], gained: 180, combo: 3, isTutorial: false, completesBoard: true))
        XCTAssertNil(lock.flash)
        XCTAssertTrue(s.progress.done)
    }

    func testRightPiecesWrongOrderCue() {
        var s = realSession()
        s.tap("AS", "TO")
        let events = s.tap("T")
        XCTAssertEqual(events, [.picked(id: "0-2", chainLength: 3, combo: 0), .nearMiss(isTutorial: false)])
        XCTAssertEqual(events[1].flash, Flash(text: "Right bubbles, wrong order. Tap a tile to put it back", tone: .hint))
    }

    func testTooManyLettersCue() {
        var s = realSession()
        s.tap("CER", "EA")
        XCTAssertEqual(s.letterCount, 5)
        XCTAssertFalse(s.tap("T").contains(.tooManyLetters), "6 letters is the longest word left, so it fits")
        XCTAssertTrue(s.tap("AC").contains(.tooManyLetters))
        XCTAssertEqual(GameEvent.tooManyLetters.flash, Flash(text: "Too many letters", tone: .bad))
    }

    func testTooManyUsesTheLongestRemainingWord() {
        var s = realSession()
        s.solve(2)
        s.tap("TO", "AC")
        XCTAssertFalse(s.chain.isEmpty)
        XCTAssertTrue(s.tap("ON").contains(.tooManyLetters), "CEREAL is gone, so 6 letters is too many")
    }

    func testMovesCountEveryPick() {
        var s = realSession()
        s.tap("AS", "TO")
        s.clearChain()
        s.solve(0)
        XCTAssertEqual(s.progress.moves, 5)
    }

    func testViewState() {
        var s = realSession()
        XCTAssertEqual(s.letterCountText, "0 letters")
        XCTAssertEqual(s.prompt, "Tap bubbles in order")
        s.tap("T")
        XCTAssertEqual(s.letterCountText, "1 letter")
        XCTAssertEqual(s.spelled, "T")
        s.clearChain()
        XCTAssertNil(s.comboText)
        XCTAssertEqual(s.heat, 0)
        var run = realSession(level: .hard)
        run.solve(0)
        XCTAssertNil(run.comboText)
        run.solve(1)
        XCTAssertEqual(run.comboText, "×2")
        XCTAssertEqual(run.heat, 1)
        run.solve(2)
        XCTAssertEqual(run.heat, 2)
        run.solve(3)
        run.solve(4)
    }

    func testSlots() {
        var s = realSession()
        XCTAssertEqual(s.slots, [.hidden(letters: 5), .hidden(letters: 5), .hidden(letters: 6)])
        s.solve(1)
        s.hint()
        XCTAssertEqual(s.slots, [.hinted("TO·…"), .solved("BACON"), .hidden(letters: 6)])
        s.hint()
        XCTAssertEqual(s.slots[0], .hinted("TO·AS·…"))
    }

    func testBubbleLookup() {
        let s = realSession()
        XCTAssertEqual(s.bubble(id: "0-0")?.text, "TO")
        XCTAssertNil(s.bubble(id: "9-9"))
    }

    func testScoreLabel() {
        var s = realSession()
        s.solve(0)
        s.solve(1)
        XCTAssertEqual(s.scoreAccessibilityLabel, "1 of 3 stars, 150 points")
    }

    func testShuffleKeepsOnlyLiveBubbles() {
        var s = realSession()
        s.solve(0)
        XCTAssertEqual(s.order.count, 9, "locking leaves the honeycomb in place")
        var rng = Mulberry32(seed: 5)
        XCTAssertEqual(s.shuffle(rng: &rng), [.shuffled])
        XCTAssertEqual(s.order.count, 6)
        XCTAssertEqual(Set(s.order), Set(s.puzzle.bubbles.map(\.id)).subtracting(["0-0", "0-1", "0-2"]))
    }

    func testShuffleIsFisherYatesOverLiveBubbles() {
        var s = GameSession(day: 1, level: .tutorial, store: ProgressStore(url: tempStoreURL(), today: 1))
        var rng = ScriptedRandom(0)
        XCTAssertEqual(s.order, ["0-2", "0-0", "0-1"])
        s.shuffle(rng: &rng)
        XCTAssertEqual(s.order, ["0-0", "0-1", "0-2"])
        XCTAssertEqual(rng.draws, 2)
    }

    func testShuffleKeepsTheChain() {
        var s = realSession()
        s.tap("AS", "TO")
        s.shuffle()
        XCTAssertEqual(s.chain, ["0-1", "0-0"])
        XCTAssertEqual(s.order.count, 9)
    }

    func testShuffleDoesNothingOnAFinishedBoard() {
        var s = realSession()
        s.solveAll()
        let order = s.order
        XCTAssertEqual(s.shuffle(), [])
        XCTAssertEqual(s.order, order)
    }

    func testReopeningRestoresTheFullOrder() {
        let store = ProgressStore(url: tempStoreURL(), today: 1)
        var s = realSession(store: store)
        s.solve(0)
        s.shuffle()
        let reopened = realSession(store: store)
        XCTAssertEqual(reopened.order, reopened.puzzle.bubbles.map(\.id))
        XCTAssertEqual(reopened.liveBubbles.count, 6)
    }
}

final class GameSessionBonusTests: XCTestCase {
    func testAutoCollect() {
        var s = realSession()
        let events = s.tap("AC", "T")
        XCTAssertEqual(events.last, .bonusCollected(word: "ACT", isSecret: false, points: 15, ids: ["1-1", "0-2"]))
        XCTAssertEqual(events.last?.flash, Flash(text: "ACT ✦ bonus +15", tone: .hint))
        XCTAssertEqual(s.chain, [])
        XCTAssertEqual(s.progress.bonus, ["ACT"])
        XCTAssertEqual(s.progress.points, 15)
    }

    func testBubblesStayInPlay() {
        var s = realSession()
        s.tap("AC", "T")
        XCTAssertEqual(s.progress.consumed, [])
        XCTAssertEqual(s.liveBubbles.count, 9)
        XCTAssertEqual(s.progress.found, [])
    }

    func testComboUnaffected() {
        var s = realSession()
        s.solve(2)
        XCTAssertEqual(s.combo, 1)
        s.tap("AC", "T")
        XCTAssertEqual(s.combo, 1)
        XCTAssertTrue(s.clean)
        s.solve(0)
        XCTAssertEqual(s.combo, 2)
    }

    func testAlreadyFoundLeavesTheChain() {
        var s = realSession()
        s.tap("AC", "T")
        let events = s.tap("AC", "T")
        XCTAssertEqual(events.last, .bonusAlreadyFound(word: "ACT"))
        XCTAssertEqual(events.last?.flash, Flash(text: "ACT · bonus already found", tone: .hint))
        XCTAssertEqual(s.chain, ["1-1", "0-2"])
        XCTAssertEqual(s.progress.points, 15)
        XCTAssertEqual(s.progress.bonus, ["ACT"])
    }

    func testAlreadyFoundSkipsLengthCues() {
        // Nine letters is too many for every word here, but a found bonus returns before the cue
        var s = syntheticSession([["TUV", "W"], ["XYZ", "A"], ["MNO", "P"]], bonus: [("MNO|TUV|XYZ", "TUVXYZMNO")])
        s.tap("TUV", "XYZ", "MNO")
        XCTAssertEqual(s.progress.bonus, ["TUVXYZMNO"])
        let events = s.tap("TUV", "XYZ", "MNO")
        XCTAssertEqual(Array(events.suffix(2)), [
            .picked(id: "2-0", chainLength: 3, combo: 0),
            .bonusAlreadyFound(word: "TUVXYZMNO"),
        ])
    }

    func testDoubleCollectIsIgnored() {
        var s = realSession()
        s.tap("AC", "T")
        s.tap("AC", "T")
        XCTAssertEqual(s.collectBonus("ACT"), [])
        XCTAssertEqual(s.progress.points, 15)
        XCTAssertEqual(s.chain, ["1-1", "0-2"], "the rejected collect leaves the tray")
    }

    func testCollectRejectsWordsNotOnThisBoard() {
        var s = realSession()
        s.tap("AC", "T")
        XCTAssertEqual(s.collectBonus("ZEBRA"), [])
        XCTAssertEqual(s.progress.bonus, ["ACT"])
    }

    func testSecretScoresTwentyFivePerLetter() {
        // Day 17 hard, Chemical elements: IRON is IR + ON
        var s = realSession(day: 17, level: .hard)
        XCTAssertNotNil(s.puzzle.bubbles.first { $0.text == "IR" }, "board changed")
        let events = s.tap("IR", "ON")
        XCTAssertEqual(events.last, .bonusCollected(word: "IRON", isSecret: true, points: 100, ids: [s.id(of: "IR"), s.id(of: "ON")]))
        XCTAssertEqual(events.last?.flash, Flash(text: "IRON ◆ secret +100", tone: .secret))
        XCTAssertEqual(s.progress.points, 100)
    }

    func testBonusWordsNeedTwoBubbles() {
        var s = syntheticSession([["ABC", "D"], ["EF", "GH"]], bonus: [("ABC", "ABC"), ("EF", "EF")])
        XCTAssertEqual(s.tap("ABC"), [.picked(id: "0-0", chainLength: 1, combo: 0)])
        XCTAssertEqual(s.progress.bonus, [])
    }

    func testAHiddenWordWinsOverABonusSpelledTheSame() {
        var s = syntheticSession([["AB", "CD"], ["EF", "GH"]], bonus: [("AB|CD", "ABCD")])
        let events = s.tap("AB", "CD")
        XCTAssertTrue(events.contains(where: \.isLock))
        XCTAssertEqual(s.progress.bonus, [])
    }

    func testABonusEarnsStars() {
        var s = syntheticSession([["AB", "C"], ["DE", "F"]], bonus: [("AB|DE", "ABDE")], secrets: ["ABDE"])
        let events = s.tap("AB", "DE")
        XCTAssertEqual(s.progress.points, 100)
        XCTAssertEqual(events, [
            .picked(id: "0-0", chainLength: 1, combo: 0),
            .picked(id: "1-0", chainLength: 2, combo: 0),
            .starEarned(stars: 3),
            .bonusCollected(word: "ABDE", isSecret: true, points: 100, ids: ["0-0", "1-0"]),
        ])
    }

    func testBonusWordSpelledDifferentWaysCounts() {
        // Day 42 medium has HOTEL twice: E|HO|L|T and EL|HO|T
        let entries = GameData.shared.bonusEntries(day: 42, level: .medium).filter { $0.word == "HOTEL" }
        XCTAssertEqual(entries.count, 2)
        let s = realSession(day: 42, level: .medium)
        XCTAssertEqual(s.bonusStillPossible, Set(GameData.shared.bonusEntries(day: 42, level: .medium).map(\.word)).count)
    }

    func testButtonIsNilWhileNothingSpellsABonus() {
        var s = realSession()
        XCTAssertNil(s.bonusButton)
        s.tap("AC")
        XCTAssertNil(s.bonusButton)
    }

    func testButtonAppearsWhenAHintRevealLeavesABonusInTheTray() {
        // The reveal removes bubbles from the tray without running checkChain, so this is how the button shows.
        var s = syntheticSession(
            [["P", "Q"], ["AB", "XY", "CD"], ["ZZ", "WW"]], bonus: [("AB|CD", "ABCD")]
        )
        s.tap("AB", "P", "CD")
        XCTAssertEqual(s.chain, ["1-0", "0-0", "1-2"])
        s.hint()
        XCTAssertEqual(s.progress.hints[0], 1)
        XCTAssertNil(s.bonusButton)
        s.hint()
        XCTAssertEqual(s.progress.found, [0], "P·Q is revealed and locked")
        XCTAssertEqual(s.chain, ["1-0", "1-2"])
        XCTAssertEqual(s.bonusButton, BonusButton(word: "ABCD", isSecret: false, label: "✦ Bonus"))
        let events = s.collectBonus("ABCD")
        XCTAssertEqual(events, [.bonusCollected(word: "ABCD", isSecret: false, points: 20, ids: ["1-0", "1-2"])])
        XCTAssertEqual(s.chain, [])
        XCTAssertNil(s.bonusButton)
    }

    func testButtonLabelForASecret() {
        var s = syntheticSession([["P", "Q"], ["AB", "CD", "XY"], ["ZZ", "WW"]], bonus: [("AB|CD", "ABCD")], secrets: ["ABCD"])
        s.tap("AB", "P")
        XCTAssertEqual(s.chain, ["1-0", "0-0"])
        s.addToChain("1-1")
        XCTAssertEqual(s.spelled, "ABPCD")
        s.hint()
        s.hint()
        XCTAssertEqual(s.bonusButton?.label, "◆ Secret")
        XCTAssertEqual(s.bonusButton?.isSecret, true)
    }

    func testButtonHiddenForABonusAlreadyHeld() {
        var s = realSession()
        s.tap("AC", "T")
        s.tap("AC", "T")
        XCTAssertEqual(s.spelled, "ACT")
        XCTAssertNil(s.bonusButton)
    }

    func testBonusStillPossible() {
        var s = realSession()
        XCTAssertEqual(s.bonusStillPossible, 9)
        s.solve(2)
        XCTAssertEqual(s.bonusStillPossible, 4, "ACT, ONTO, TON, TOT need no CEREAL bubble")
        s.tap("AC", "T")
        XCTAssertEqual(s.bonusStillPossible, 3)
        s.solve(0)
        XCTAssertEqual(s.bonusStillPossible, 0)
    }

    func testBonusStillPossibleCountsRepeatedChunks() {
        // TOT needs T and TO; a word needing the same chunk twice needs two bubbles
        let s = syntheticSession([["AB", "CD"]], bonus: [("AB|AB", "ABAB"), ("AB|CD", "ABCDX")])
        XCTAssertEqual(s.bonusStillPossible, 1)
    }

    func testBoardWithNoBonusWords() {
        // Day 3 easy has none in the data.
        XCTAssertTrue(GameData.shared.bonusEntries(day: 3, level: .easy).isEmpty)
        var s = realSession(day: 3)
        XCTAssertEqual(s.bonusStillPossible, 0)
        XCTAssertNil(s.bonusBar)
        s.solveAll()
        XCTAssertTrue(s.progress.done)
    }

    func testDaysPastTheBonusData() {
        var s = realSession(day: 250, level: .medium)
        XCTAssertEqual(s.bonusStillPossible, 0)
        s.solveAll()
        XCTAssertTrue(s.progress.done)
    }

    func testBonusBarNewestFirst() {
        var s = realSession()
        XCTAssertNil(s.bonusBar, "hidden until the first bonus word")
        s.tap("AC", "T")
        s.tap("EA", "T")
        XCTAssertEqual(s.bonusBar, [BonusChip(word: "EAT", isSecret: false), BonusChip(word: "ACT", isSecret: false)])
    }
}
