import WordBubblesCore
import XCTest
@testable import WordBubbles

final class ChoreographyTests: XCTestCase {
    let flight = 0.32
    let lead = Choreography.frameLead

    private func cues(_ events: [GameEvent], at time: Double) -> [Cue] {
        Choreography.timeline(for: events, flight: flight)
            .filter { abs($0.at - time) < 1e-6 }.map(\.cue)
    }

    private func locked(_ wi: Int = 1, combo: Int = 2, completes: Bool = false) -> GameEvent {
        .wordLocked(wordIndex: wi, word: "PEAR", ids: ["1-0", "1-1"], gained: 80, combo: combo, isTutorial: false, completesBoard: completes)
    }

    func testPickPlaysPitchedSoundAndLightHapticAtOnce() {
        let events: [GameEvent] = [.picked(id: "0-0", chainLength: 3, combo: 2)]
        XCTAssertEqual(cues(events, at: 0), [.sound(.pick(index: 2, lift: 2)), .haptic(.pick)])
        XCTAssertEqual(Choreography.blockDuration(for: events, flight: flight), 0)
    }

    func testUnpickSoundAndBrokenCombo() {
        XCTAssertEqual(cues([.unpicked(ids: ["a"]), .comboBroken(wasCombo: true)], at: 0), [.sound(.unpick), .sound(.crack)])
        XCTAssertEqual(cues([.comboBroken(wasCombo: false)], at: 0), [])
    }

    func testWrongAndNearShakeTheTray() {
        let wrong = GameEvent.tooManyLetters
        XCTAssertEqual(cues([wrong], at: 0), [.sound(.wrong), .shakeTray, .flash(wrong.flash!)])
        let near = GameEvent.nearMiss(isTutorial: false)
        XCTAssertEqual(cues([near], at: 0), [.sound(.near), .shakeTray, .flash(near.flash!)])
    }

    func testAlreadyFoundBonusOnlyFlashes() {
        let e = GameEvent.bonusAlreadyFound(word: "TEA")
        XCTAssertEqual(cues([e], at: 0), [.flash(e.flash!)])
    }

    func testLockTimeline() {
        let word = locked()
        let events: [GameEvent] = [.picked(id: "1-1", chainLength: 2, combo: 1), .starEarned(stars: 1), word]
        XCTAssertEqual(cues(events, at: 0.2), [.fuseTray(.accent, ids: ["1-0", "1-1"])])
        XCTAssertEqual(cues(events, at: 0.62), [
            .sound(.lock(combo: 2)), .haptic(.lock),
            .commit(.word(index: 1, word: "PEAR", ids: ["1-0", "1-1"], combo: 2)),
            .sound(.earn), .bumpScore, .flash(GameEvent.starEarned(stars: 1).flash!),
            .releaseInput,
        ])
        XCTAssertEqual(cues(events, at: 0.62 + lead + flight), [.landSlot(1), .flash(word.flash!)])
        XCTAssertEqual(Choreography.blockDuration(for: events, flight: flight), 0.62, accuracy: 1e-9)
    }

    func testFinishingWordHoldsInputUntilTheCardAndFlashesNoWord() {
        let events: [GameEvent] = [locked(completes: true), .finished]
        let land = 0.62 + lead + flight
        XCTAssertFalse(cues(events, at: 0.62).contains(.releaseInput))
        XCTAssertEqual(cues(events, at: land), [.landSlot(1), .sound(.win), .haptic(.finish), .celebrate, .showResult, .releaseInput])
        XCTAssertEqual(Choreography.blockDuration(for: events, flight: flight), land, accuracy: 1e-9)
    }

    func testBonusTimelineGoldAndSecret() {
        let gold = GameEvent.bonusCollected(word: "PEA", isSecret: false, points: 15, ids: ["0-0", "1-0"])
        XCTAssertEqual(cues([gold], at: 0.2), [.freezeTray])
        XCTAssertEqual(cues([gold], at: 0.4), [.fuseTray(.gold, ids: ["0-0", "1-0"])])
        XCTAssertEqual(cues([gold], at: 0.82), [
            .commit(.bonus(word: "PEA", tone: .gold, ids: ["0-0", "1-0"])), .sound(.bonus), .releaseInput,
        ])
        XCTAssertEqual(cues([gold], at: 0.82 + lead + flight), [.landChip("PEA"), .flash(gold.flash!)])

        let secret = GameEvent.bonusCollected(word: "PEA", isSecret: true, points: 75, ids: ["0-0"])
        XCTAssertEqual(cues([secret], at: 0.4), [.fuseTray(.secret, ids: ["0-0"])])
    }

    func testHintAndReveal() {
        let hint = GameEvent.hintRevealed(wordIndex: 0, chunks: ["PE"], firstHint: true)
        XCTAssertEqual(cues([.comboBroken(wasCombo: false), hint], at: 0), [.sound(.hint), .flash(hint.flash!)])

        let reveal = GameEvent.wordRevealed(wordIndex: 2, word: "PEAR", ids: ["2-0"], points: 20, firstHint: false)
        XCTAssertEqual(cues([reveal], at: 0), [.sound(.hint), .popBubbles(["2-0"]), .flash(reveal.flash!)])
        XCTAssertEqual(cues([reveal], at: 0.42), [.commit(.reveal(index: 2, ids: ["2-0"])), .releaseInput])
        XCTAssertEqual(Choreography.blockDuration(for: [reveal], flight: flight), 0.42, accuracy: 1e-9)

        XCTAssertEqual(cues([reveal, .finished], at: 0.42), [
            .commit(.reveal(index: 2, ids: ["2-0"])), .sound(.win), .haptic(.finish), .celebrate, .showResult, .releaseInput,
        ])
    }

    func testStarEarnedByARevealIsImmediate() {
        let reveal = GameEvent.wordRevealed(wordIndex: 2, word: "PEAR", ids: ["2-0"], points: 20, firstHint: false)
        let star = GameEvent.starEarned(stars: 2)
        XCTAssertEqual(cues([star, reveal], at: 0), [
            .sound(.earn), .bumpScore, .flash(star.flash!), .sound(.hint), .popBubbles(["2-0"]), .flash(reveal.flash!),
        ])
    }

    func testShuffle() {
        XCTAssertEqual(cues([.shuffled], at: 0), [.sound(.shuffle)])
    }

    func testReduceMotionKeepsOrderWithNoFlight() {
        let events: [GameEvent] = [locked(completes: false)]
        let timeline = Choreography.timeline(for: events, flight: 0)
        let land = timeline.first { $0.cue == .landSlot(1) }
        XCTAssertEqual(land?.at ?? 0, 0.62, accuracy: 1e-9)
    }

    func testTimelineIsSortedStably() {
        let timeline = Choreography.timeline(for: [.starEarned(stars: 1), locked()], flight: flight)
        XCTAssertEqual(timeline.map(\.at), timeline.map(\.at).sorted())
    }
}

final class TrayLayoutTests: XCTestCase {
    private func measure(_ s: String) -> Double { Double(s.count) * 10 }

    func testCentersTilesWithGapAndPadding() {
        let frames = TrayLayout.frames(texts: ["AB", "C"], pillWidth: 300, pillHeight: 52, locked: false, measure: measure)
        XCTAssertEqual(frames.scale, 1)
        XCTAssertEqual(frames.rects[0].width, 42)   // 20 + 22 padding
        XCTAssertEqual(frames.rects[1].width, 42)   // min-width
        XCTAssertEqual(frames.rects[1].minX - frames.rects[0].maxX, 5)
        XCTAssertEqual((frames.rects[0].minX + frames.rects[1].maxX) / 2, 150)
        XCTAssertEqual(frames.rects[0].midY, 26)
        XCTAssertEqual(frames.rects[0].height, 42)
    }

    func testLockedTilesTouchAndGetEndPadding() {
        let frames = TrayLayout.frames(texts: ["ABCD", "EFGH"], pillWidth: 300, pillHeight: 52, locked: true, measure: measure)
        XCTAssertEqual(frames.rects[1].minX, frames.rects[0].maxX)
        XCTAssertEqual(frames.rects[0].width, 40 + 22 + 3)
        XCTAssertEqual(frames.rects[1].width, 40 + 22 + 3)
    }

    func testShrinksToFitBetweenBadgeAndClear() {
        let texts = ["ABC", "DEF", "GHI", "JKL", "MNO", "PQR"]
        let frames = TrayLayout.frames(texts: texts, pillWidth: 300, pillHeight: 52, locked: false, measure: measure)
        XCTAssertLessThan(frames.scale, 1)
        let span = frames.rects.last!.maxX - frames.rects[0].minX
        XCTAssertLessThanOrEqual(span, 300 - 2 * TrayLayout.edgeInset + 0.001)
        XCTAssertEqual((frames.rects[0].minX + frames.rects.last!.maxX) / 2, 150, accuracy: 0.001)
    }

    func testCountHidesWhenTilesReachIt() {
        let narrow = TrayLayout.frames(texts: ["AB"], pillWidth: 300, pillHeight: 52, locked: false, measure: measure)
        XCTAssertTrue(narrow.roomForCount)
        let wide = TrayLayout.frames(texts: ["ABCDEF", "GHIJKL", "MNOPQR"], pillWidth: 300, pillHeight: 52, locked: false, measure: measure)
        XCTAssertFalse(wide.roomForCount)
    }

    func testEmpty() {
        XCTAssertTrue(TrayLayout.frames(texts: [], pillWidth: 300, pillHeight: 52, locked: false, measure: measure).rects.isEmpty)
    }
}
