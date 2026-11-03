import CoreGraphics
import WordBubblesCore
import XCTest
@testable import WordBubbles

/// Runs delayed work on a virtual clock.
@MainActor
final class VirtualScheduler: Scheduling {
    private var queue: [(at: Double, order: Int, handle: ScheduledWork, work: @MainActor () -> Void)] = []
    private var order = 0
    private(set) var time = 0.0

    @discardableResult
    func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        order += 1
        let handle = ScheduledWork()
        queue.append((time + seconds, order, handle, work))
        return handle
    }

    func advance(_ seconds: Double) {
        let end = time + seconds
        while let next = queue.filter({ $0.at <= end + 1e-9 }).min(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
            queue.removeAll { $0.order == next.order }
            time = max(time, next.at)
            if !next.handle.isCancelled { next.work() }
        }
        time = end
    }
}

@MainActor
final class RecordingSound: SoundPlaying {
    var isOn = true
    var played: [SoundEffect] = []
    var suspended = 0
    var resumed = 0
    func play(_ effect: SoundEffect) { played.append(effect) }
    func suspend() { suspended += 1 }
    func resume() { resumed += 1 }
}

@MainActor
final class RecordingHaptics: HapticPlaying {
    var played: [Haptic] = []
    func play(_ haptic: Haptic) { played.append(haptic) }
}

struct FailingTransport: RecordsTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
final class GameModelTests: XCTestCase {
    var scheduler: VirtualScheduler!
    var sound: RecordingSound!
    var haptics: RecordingHaptics!
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    var motionReduced = false
    var defaults: UserDefaults!

    func makeModel(tutorialDone: Bool = true, today: Int? = nil) -> GameModel {
        scheduler = VirtualScheduler()
        sound = RecordingSound()
        haptics = RecordingHaptics()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wb-app-\(UUID().uuidString)/progress.json")
        let day = today ?? plainDay()
        date = date.addingTimeInterval(Double(day - Engine.dayNumber(for: date)) * 86_400)
        let store = ProgressStore(url: url, today: day)
        if tutorialDone { store.setTutorialDone() }
        defaults = UserDefaults(suiteName: "wb-tests-\(UUID().uuidString)")
        let model = GameModel(GameDependencies(
            store: store, records: RecordsClient(transport: FailingTransport()), place: .nowhere,
            sound: sound, haptics: haptics, scheduler: scheduler,
            now: { [unowned self] in self.date },
            measure: { Double($0.count) * 12 }, reduceMotion: { [unowned self] in self.motionReduced },
            usesNetwork: false, defaults: defaults
        ))
        model.boardMeasured(CGRect(x: 16, y: 300, width: 358, height: 300))
        model.trayMeasured(CGRect(x: 16, y: 200, width: 358, height: 52))
        for index in 0..<5 { model.slotFrames[index] = CGRect(x: Double(index) * 60, y: 100, width: 56, height: 30) }
        return model
    }

    /// A day whose Easy words have no bonus word among their first pieces, so spelling one goes straight to the lock.
    func plainDay() -> Int {
        (2...400).first { day in
            let puzzle = GameData.shared.puzzle(day: day, level: .easy)
            let keys = Set(GameData.shared.bonusEntries(day: day, level: .easy).map(\.key))
            return puzzle.chunksByWord.allSatisfy { chunks in
                chunks.indices.allSatisfy { !keys.contains(chunks[...$0].sorted().joined(separator: "|")) }
            }
        }!
    }

    func center(_ model: GameModel, _ id: String) -> CGPoint {
        model.centers.first { $0.id == id }!.center
    }

    func tap(_ model: GameModel, _ id: String) {
        model.touchBegan(at: center(model, id))
        model.touchEnded()
    }

    /// Ids of a word's chunks, in order.
    func ids(_ model: GameModel, word: Int) -> [String] {
        model.session.puzzle.chunksByWord[word].indices.map { "\(word)-\($0)" }
    }

    func spell(_ model: GameModel, word: Int) {
        for id in ids(model, word: word) { tap(model, id) }
    }

    func testFirstLaunchOpensTheTutorial() {
        let model = makeModel(tutorialDone: false)
        XCTAssertEqual(model.level, .tutorial)
        XCTAssertTrue(model.isTutorial)
        XCTAssertEqual(model.prompt, "Tap RA → IN → BOW")
        XCTAssertNil(model.clock)
    }

    func testPickAddsLandingTileFlightSoundAndHaptic() {
        let model = makeModel()
        let id = model.session.order[0]
        tap(model, id)
        XCTAssertEqual(model.tiles.map(\.id), [id])
        XCTAssertTrue(model.tiles[0].landing)
        XCTAssertTrue(model.bubbleStates[id]!.selected)
        XCTAssertEqual(model.flights.count, 1)
        XCTAssertEqual(model.flights[0].kind, .toTray)
        XCTAssertEqual(sound.played, [.pick(index: 0, lift: 0)])
        XCTAssertEqual(haptics.played, [.pick])
        scheduler.advance(0.33)
        XCTAssertFalse(model.tiles[0].landing)
        XCTAssertTrue(model.flights.isEmpty)
    }

    func testTappingTilePutsItBack() {
        let model = makeModel()
        let id = model.session.order[0]
        tap(model, id)
        scheduler.advance(0.4)
        model.tapTile(id)
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertEqual(model.flights.first?.kind, .toBoard)
        XCTAssertTrue(model.bubbleStates[id]!.selected, "stays faded until the tile lands")
        scheduler.advance(0.33)
        XCTAssertFalse(model.bubbleStates[id]!.selected)
    }

    func testRepickDuringReturnFlightStaysSelected() {
        let model = makeModel()
        let id = model.session.order[0]
        tap(model, id)
        scheduler.advance(0.4)
        model.tapTile(id)
        scheduler.advance(0.1)
        tap(model, id)
        scheduler.advance(0.4)
        XCTAssertTrue(model.bubbleStates[id]!.selected)
        XCTAssertEqual(model.tiles.map(\.id), [id])
    }

    func testClearFliesEveryTileHome() {
        let model = makeModel()
        tap(model, model.session.order[0])
        tap(model, model.session.order[1])
        scheduler.advance(0.4)
        sound.played = []
        model.clearTray()
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertEqual(model.flights.count, 2)
        XCTAssertEqual(sound.played, [.unpick])
    }

    func testSwipeOnlyActsOnNewBubbleAndSlideBackUndoes() {
        let model = makeModel()
        // two bubbles that do not make a word between them
        let a = model.session.order[0], b = model.session.order[1]
        model.touchBegan(at: center(model, a))
        model.touchMoved(to: center(model, a))
        model.touchMoved(to: center(model, a))
        XCTAssertEqual(model.tiles.count, 1, "samples inside one bubble are ignored")
        model.touchMoved(to: center(model, b))
        XCTAssertEqual(model.tiles.map(\.id), [a, b])
        model.touchMoved(to: center(model, a))
        XCTAssertEqual(model.tiles.map(\.id), [a], "slide back undoes")
        model.touchEnded()
    }

    func testReturningToTheExactStartPointIsAMoveNotATap() {
        let model = makeModel()
        let a = model.session.order[0], b = model.session.order[1]
        model.touch(at: center(model, a))
        model.touch(at: center(model, b))
        model.touch(at: center(model, a))
        model.touchEnded()
        XCTAssertEqual(model.tiles.map(\.id), [a])
        model.touch(at: center(model, a))
        model.touchEnded()
        XCTAssertTrue(model.tiles.isEmpty, "a new touch on a picked bubble puts it back")
    }

    func testMovesOutsideAnyBubbleAreIgnored() {
        let model = makeModel()
        model.touchBegan(at: CGPoint(x: -500, y: -500))
        model.touchMoved(to: center(model, model.session.order[0]))
        XCTAssertTrue(model.tiles.isEmpty, "no gesture began")
    }

    func testLockChoreography() {
        let model = makeModel()
        let word = ids(model, word: 0)
        spell(model, word: 0)
        XCTAssertTrue(model.inputBlocked)
        XCTAssertEqual(model.tiles.map(\.id), word, "the tray keeps the word though the chain is empty")
        XCTAssertTrue(model.session.chain.isEmpty)
        XCTAssertEqual(model.points, 0, "score waits for the slot")
        XCTAssertNil(model.lockTone)

        scheduler.advance(0.21)
        XCTAssertEqual(model.lockTone, .accent)
        XCTAssertTrue(word.allSatisfy { model.bubbleStates[$0]!.popping })
        XCTAssertFalse(model.showsLetterCount)
        XCTAssertTrue(model.flights.filter { $0.kind == .toTray }.isEmpty)

        scheduler.advance(0.42)
        XCTAssertFalse(model.inputBlocked, "free at 620ms")
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertGreaterThan(model.points, 0)
        XCTAssertTrue(word.allSatisfy { model.bubbleStates[$0]!.consumed })
        XCTAssertTrue(sound.played.contains(.lock(combo: 1)))
        XCTAssertTrue(haptics.played.contains(.lock))
        XCTAssertTrue(model.slots[0].arriving)

        scheduler.advance(0.03)
        XCTAssertEqual(model.flights.last?.kind, .word(.accent))

        scheduler.advance(0.33)
        XCTAssertFalse(model.slots[0].arriving)
        XCTAssertNotNil(model.flash)
        XCTAssertTrue(model.flash!.text.hasPrefix(model.session.puzzle.words[0]))
        XCTAssertTrue(model.flights.isEmpty)

        scheduler.advance(2)
        XCTAssertNil(model.flash, "clears after 1.9s")
    }

    func testInputIgnoredWhileBlocked() {
        let model = makeModel()
        spell(model, word: 0)
        let other = ids(model, word: 1)[0]
        model.touchBegan(at: center(model, other))
        model.touchEnded()
        model.useHint()
        model.shuffle()
        model.select(level: .hard)
        XCTAssertEqual(model.tiles.count, ids(model, word: 0).count)
        XCTAssertEqual(model.level, .easy)
        XCTAssertFalse(model.session.progress.usedHint)
    }

    func testCombosShowAndBump() {
        let model = makeModel()
        spell(model, word: 0)
        scheduler.advance(1)
        spell(model, word: 1)
        scheduler.advance(1)
        XCTAssertEqual(model.comboText, "×2")
        XCTAssertEqual(model.comboBump, 1)
        XCTAssertEqual(model.heat, 1)
    }

    func testFullBoardReachesResultCardAtLanding() {
        let model = makeModel()
        let count = model.session.puzzle.words.count
        for word in 0..<count {
            XCTAssertNil(model.result)
            // a chunk of this word can be a bonus word: solve with the tray diffed, as a player would
            var guardCount = 0
            while !model.session.progress.found.contains(word) && guardCount < 8 {
                for id in ids(model, word: word) {
                    tap(model, id)
                    scheduler.advance(0.01)
                    if model.inputBlocked { break }
                }
                scheduler.advance(1.2)
                guardCount += 1
            }
        }
        XCTAssertNotNil(model.result)
        XCTAssertFalse(model.inputBlocked)
        XCTAssertTrue(sound.played.contains(.win))
        XCTAssertTrue(haptics.played.contains(.finish))
        XCTAssertEqual(model.tabs.first { $0.level == .easy }?.badge, "✓")
        if case .board = model.result! {} else { XCTFail("expected a board card") }
    }

    func testStarsLandWithSoundsOnlyTheFirstTime() {
        let model = makeModel()
        finishEasy(model)
        scheduler.advance(1)
        let landed = sound.played.filter { if case .pick(index: 4, lift: 0) = $0 { return true } else { return false } }
        XCTAssertFalse(landed.isEmpty)
        XCTAssertTrue(model.resultAnimates)
        model.select(level: .medium)
        model.select(level: .easy)
        XCTAssertFalse(model.resultAnimates)
    }

    func finishEasy(_ model: GameModel) {
        for word in model.session.puzzle.words.indices {
            var guardCount = 0
            while !model.session.progress.found.contains(word) && guardCount < 8 {
                for id in ids(model, word: word) {
                    tap(model, id)
                    scheduler.advance(0.01)
                    if model.inputBlocked { break }
                }
                scheduler.advance(1.2)
                guardCount += 1
            }
        }
    }

    /// A day and pair of bubble ids on it that spell a bonus word.
    func bonusBoard() -> (day: Int, ids: [String], word: String, secret: Bool)? {
        for day in 2...200 {
            let puzzle = GameData.shared.puzzle(day: day, level: .easy)
            for entry in GameData.shared.bonusEntries(day: day, level: .easy) {
                let pieces = entry.key.split(separator: "|").map(String.init)
                guard pieces.count == 2, pieces[0] != pieces[1] else { continue }
                for order in [pieces, pieces.reversed()] where order.joined() == entry.word {
                    let ids = order.compactMap { text in puzzle.bubbles.first { $0.text == text }?.id }
                    if ids.count == 2 {
                        return (day, ids, entry.word, GameData.shared.isSecret(word: entry.word, theme: puzzle.theme))
                    }
                }
            }
        }
        return nil
    }

    func testBonusFusesThenFliesIntoTheScoreAndBubblesStayInPlay() throws {
        let board = try XCTUnwrap(bonusBoard())
        let model = makeModel(today: board.day)
        model.scoreFrame = CGRect(x: 150, y: 60, width: 90, height: 40)
        board.ids.forEach { tap(model, $0) }
        XCTAssertTrue(model.inputBlocked)
        scheduler.advance(0.21)
        XCTAssertFalse(model.showsLetterCount)
        XCTAssertNil(model.lockTone)
        scheduler.advance(0.2)
        XCTAssertEqual(model.lockTone, board.secret ? .secret : .gold)
        scheduler.advance(0.42)
        XCTAssertFalse(model.inputBlocked)
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertTrue(sound.played.contains(.bonus))
        XCTAssertTrue(board.ids.allSatisfy { !model.bubbleStates[$0]!.selected && !model.bubbleStates[$0]!.consumed })
        scheduler.advance(0.03)
        XCTAssertEqual(model.flights.last?.kind, .word(board.secret ? .secret : .gold))
        scheduler.advance(0.33)
        XCTAssertFalse(model.flash!.text.contains(board.word), "the word itself stays private")
        XCTAssertEqual(model.session.progress.bonus, [board.word], "banked, and kept for the score screen")
    }

    func testVoiceOverActivationPicksAndPutsBack() {
        let model = makeModel()
        let id = model.session.order[0]
        model.activateBubble(id)
        XCTAssertEqual(model.tiles.map(\.id), [id])
        model.activateBubble(id)
        XCTAssertTrue(model.tiles.isEmpty)
    }

    func testHintShowsBadgeAndFlash() {
        let model = makeModel()
        model.useHint()
        model.useHint()
        XCTAssertEqual(model.bubbleStates["0-0"]?.hintNumber, 1)
        XCTAssertTrue(model.flash!.text.hasPrefix("Starts with"))
        XCTAssertEqual(sound.played, [.hint])
        XCTAssertEqual(model.slots[0].slot, model.session.slots[0])
    }

    func testRevealPopsThenConsumes() {
        let model = makeModel()
        var guardCount = 0
        while model.session.progress.found.isEmpty && guardCount < 10 {
            model.useHint()
            guardCount += 1
        }
        XCTAssertTrue(model.inputBlocked)
        let word = ids(model, word: 0)
        XCTAssertTrue(word.allSatisfy { model.bubbleStates[$0]!.popping })
        scheduler.advance(0.43)
        XCTAssertTrue(word.allSatisfy { model.bubbleStates[$0]!.consumed })
        XCTAssertFalse(model.inputBlocked)
    }

    func testRevealRemovesItsTileWithoutAFlight() {
        let model = makeModel()
        let first = ids(model, word: 0)[0]
        tap(model, first)
        scheduler.advance(0.4)
        var guardCount = 0
        while model.session.progress.found.isEmpty && guardCount < 10 {
            model.useHint()
            guardCount += 1
        }
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertTrue(model.flights.isEmpty)
    }

    func testShuffleRelaysOutAndPlaysSound() {
        let model = makeModel()
        spell(model, word: 0)
        scheduler.advance(1)
        let before = model.centers.count
        model.shuffle()
        XCTAssertLessThan(model.centers.count, before)
        XCTAssertEqual(model.orderCount, model.centers.count)
        XCTAssertTrue(sound.played.contains(.shuffle))
    }

    func testReduceMotionHasNoFlights() {
        motionReduced = true
        let model = makeModel()
        spell(model, word: 0)
        XCTAssertTrue(model.flights.isEmpty)
        XCTAssertFalse(model.tiles.contains { $0.landing })
        scheduler.advance(0.7)
        XCTAssertTrue(model.flights.isEmpty)
        XCTAssertFalse(model.slots[0].arriving)
        XCTAssertNotNil(model.flash)
    }

    func testOpeningABoardCancelsAnythingPending() {
        let model = makeModel()
        let id = model.session.order[0]
        tap(model, id)
        model.select(level: .medium)
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertTrue(model.flights.isEmpty)
        XCTAssertEqual(model.level, .medium)
        scheduler.advance(1)
    }

    func testDayNavigation() {
        let model = makeModel()
        let today = model.day
        XCTAssertFalse(model.canGoForward)
        XCTAssertFalse(model.showsToday)
        model.previousDay()
        XCTAssertEqual(model.day, today - 1)
        XCTAssertEqual(model.slideDirection, .right)
        XCTAssertTrue(model.showsToday)
        XCTAssertTrue(model.canGoForward)
        model.goToToday()
        XCTAssertEqual(model.day, today)
        XCTAssertEqual(model.slideDirection, .left)
        XCTAssertEqual(model.slideCount, 2)
    }

    func testRolloverOnActivationMovesToTheNewDay() {
        let model = makeModel()
        let today = model.day
        model.didEnterBackground()
        date = date.addingTimeInterval(86_400)
        model.didBecomeActive()
        XCTAssertEqual(model.day, today + 1)
        XCTAssertEqual(model.store.today, today + 1)
    }

    func testRolloverOnTheMinuteTimer() {
        let model = makeModel()
        let today = model.day
        date = date.addingTimeInterval(86_400)
        scheduler.advance(61)
        XCTAssertEqual(model.day, today + 1)
    }

    func testBackgroundPausesTheClockAndSound() {
        let model = makeModel()
        model.didEnterBackground()
        let frozen = model.session.liveElapsed
        date = date.addingTimeInterval(500)
        XCTAssertEqual(model.session.liveElapsed, frozen, accuracy: 0.001)
        XCTAssertEqual(sound.suspended, 1)
        model.didBecomeActive()
        XCTAssertEqual(sound.resumed, 1)
    }

    func testClockPollsEveryHalfSecond() {
        let model = makeModel()
        date = date.addingTimeInterval(65)
        scheduler.advance(0.6)
        XCTAssertEqual(model.clock?.timeText, "1:05")
    }

    func testSoundToggleChirpsOnlyWhenTurningOn() {
        let model = makeModel()
        model.toggleSound()
        XCTAssertFalse(model.soundOn)
        XCTAssertTrue(sound.played.isEmpty)
        model.toggleSound()
        XCTAssertTrue(model.soundOn)
        XCTAssertEqual(sound.played, [.pick(index: 2, lift: 0)])
    }

    func testRecordWinsUpdateTheCardAndPlayEarn() {
        let model = makeModel()
        finishEasy(model)
        sound.played = []
        let before = model.result
        model.recordsFinished(RecordWins(world: true), day: model.day, level: model.level, snapshot: [:], all: [:])
        XCTAssertEqual(sound.played, [.earn])
        XCTAssertNotNil(model.result)
        XCTAssertNotNil(before)
        XCTAssertTrue(model.store.record(day: model.day, level: .easy).newRecord)
    }

    func testBubblesKeepOrderMapping() {
        let model = makeModel()
        XCTAssertEqual(model.centers.map(\.id), model.session.order)
        XCTAssertEqual(model.bubbleStates[model.session.order[0]]?.point, model.centers[0].center)
    }

    func testTileFramesRecomputeWhenTrayIsMeasured() {
        let model = makeModel()
        tap(model, model.session.order[0])
        let before = model.tiles[0].frame
        model.trayMeasured(CGRect(x: 0, y: 0, width: 500, height: 52))
        XCTAssertNotEqual(model.tiles[0].frame, before)
    }

    // MARK: Hints ask before they cost the medal

    func testTheFirstHintAsksBeforeGivingUpTheMedal() {
        let model = makeModel()
        model.useHint()
        XCTAssertTrue(model.hintArmed)
        XCTAssertFalse(model.session.progress.usedHint, "nothing is spent yet")
        XCTAssertTrue(sound.played.isEmpty)
        model.useHint()
        XCTAssertFalse(model.hintArmed)
        XCTAssertTrue(model.session.progress.usedHint)
    }

    func testTheHintQuestionLapsesOnItsOwn() {
        let model = makeModel()
        model.useHint()
        scheduler.advance(GameModel.hintArmSeconds + 0.1)
        XCTAssertFalse(model.hintArmed)
        model.useHint()
        XCTAssertFalse(model.session.progress.usedHint, "it asks again")
    }

    func testTouchingTheBoardCancelsTheHintQuestion() {
        let model = makeModel()
        model.useHint()
        tap(model, ids(model, word: 0)[0])
        XCTAssertFalse(model.hintArmed)
    }

    func testLeavingTheBoardCancelsTheHintQuestion() {
        let model = makeModel()
        model.useHint()
        model.select(level: .medium)
        XCTAssertFalse(model.hintArmed)
    }

    func testHintsAfterTheFirstDoNotAsk() {
        let model = makeModel()
        model.useHint()
        model.useHint()
        let hints = model.session.progress.hints
        model.useHint()
        XCTAssertFalse(model.hintArmed)
        XCTAssertNotEqual(model.session.progress.hints, hints, "it acted at once")
    }

    func testNoMedalLeftMeansNothingToAsk() {
        let model = makeModel()
        date = date.addingTimeInterval(590)
        model.useHint()
        XCTAssertFalse(model.hintArmed)
        XCTAssertTrue(model.session.progress.usedHint)
    }

    // MARK: Bonus words wait for the score screen

    func testAnInlineBonusLeavesTheTrayAndTheSwipeAlone() {
        let (model, chunks) = makeModelWithInlineBonus()
        for chunk in chunks { tap(model, chunk) }
        XCTAssertFalse(model.inputBlocked)
        XCTAssertEqual(model.tiles.map(\.id), chunks)
        XCTAssertEqual(model.session.progress.bonus.count, 1)
        XCTAssertEqual(sound.played.last, .bonus)
        XCTAssertFalse(model.flash!.text.contains(model.session.progress.bonus[0]), "the word itself stays private")
    }

    /// A real board where the first pieces of a hidden word also spell a bonus word.
    private func makeModelWithInlineBonus() -> (GameModel, [String]) {
        for day in 2...200 {
            let puzzle = GameData.shared.puzzle(day: day, level: .easy)
            let keys = Set(GameData.shared.bonusEntries(day: day, level: .easy).map(\.key))
            for (wordIndex, chunks) in puzzle.chunksByWord.enumerated() {
                for end in chunks.indices.dropFirst().dropLast() where keys.contains(chunks[...end].sorted().joined(separator: "|")) {
                    let model = makeModel(today: day)
                    return (model, (0...end).map { "\(wordIndex)-\($0)" })
                }
            }
        }
        fatalError("no such board")
    }

    // MARK: The tray's quiet text

    func testThePromptCountsWhatIsLeftOnceAWordIsFound() {
        let model = makeModel()
        XCTAssertEqual(model.prompt, "Tap bubbles in order")
        spell(model, word: 0)
        scheduler.advance(1)
        let left = model.session.puzzle.words.count - 1
        XCTAssertEqual(model.prompt, "\(left) words left")
        spell(model, word: 1)
        scheduler.advance(1)
        XCTAssertEqual(model.prompt, "1 word left")
    }

    // MARK: Header

    func testDayTitle() {
        let model = makeModel()
        XCTAssertEqual(model.dayTitle, "Today")
        model.previousDay()
        XCTAssertEqual(model.dayTitle, model.formatter.short(day: model.day))
    }

    // MARK: Tutorial

    func testTheTutorialCanBeSkipped() {
        let model = makeModel(tutorialDone: false)
        XCTAssertEqual(model.level, .tutorial)
        model.skipTutorial()
        XCTAssertEqual(model.level, .easy)
        XCTAssertTrue(model.store.tutorialDone)
    }

    // MARK: Settings

    func testHapticsCanBeTurnedOffAndStayOff() {
        let model = makeModel()
        XCTAssertTrue(model.hapticsOn)
        model.setHaptics(false)
        tap(model, ids(model, word: 0)[0])
        XCTAssertTrue(haptics.played.isEmpty)
        XCTAssertEqual(defaults.object(forKey: GameModel.hapticsKey) as? Bool, false)
    }

    func testPostingTimesDefaultsOnAndIsRemembered() {
        let model = makeModel()
        XCTAssertTrue(model.postsTimes)
        model.setPostsTimes(false)
        XCTAssertFalse(model.postsTimes)
        XCTAssertEqual(defaults.object(forKey: GameModel.postsTimesKey) as? Bool, false)
    }
}
