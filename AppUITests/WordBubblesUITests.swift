import WordBubblesCore
import XCTest

/// Drives the real app with real touches. Words are looked up in `GameData`, the same bundled data the app plays.
final class WordBubblesUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dark = false

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Helpers

    @discardableResult
    private func launch(skipTutorial: Bool) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (skipTutorial ? ["-uiTestingSkipTutorial"] : []) + (dark ? ["-uiTestingDark"] : [])
        app.launch()
        return app
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func bubble(_ text: String) -> XCUIElement {
        any("bubble-\(text)")
    }

    private var today: Int { Engine.dayNumber(for: Date()) }

    private func wait(_ seconds: TimeInterval) {
        let gate = expectation(description: "wait")
        gate.isInverted = true
        wait(for: [gate], timeout: seconds)
    }

    /// One finger along these points, in window coordinates, so a swipe can bend and double back.
    private func swipe(through points: [CGPoint], secondsPerLeg: Double = 0.28) {
        let path = XCPointerEventPath(forTouchAt: points[0], offset: 0.02)
        var offset = 0.1
        for point in points.dropFirst() {
            offset += secondsPerLeg
            path.move(to: point, atOffset: offset)
        }
        path.liftUp(atOffset: offset + 0.05)
        let record = XCSynthesizedEventRecord(name: "swipe", interfaceOrientation: 1)
        record.add(path)
        let done = expectation(description: "swipe synthesized")
        XCUIDevice.shared.eventSynthesizer().synthesizeEvent(record) { _, _ in done.fulfill() }
        wait(for: [done], timeout: 20)
    }

    private func center(_ element: XCUIElement) -> CGPoint {
        CGPoint(x: element.frame.midX, y: element.frame.midY)
    }

    /// True when the straight line from a to b stays clear of every other bubble.
    private func legIsClear(_ a: CGPoint, _ b: CGPoint, others: [CGPoint], radius: CGFloat) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(dx * dx + dy * dy, 1)
        return others.allSatisfy { point in
            let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / length, 0), 1)
            return hypot(a.x + t * dx - point.x, a.y + t * dy - point.y) > radius * 1.25
        }
    }

    /// Spells a word by swiping where the path is clear and lifting the finger where it would cross another bubble.
    /// Returns how many strokes were swipes across two bubbles or more.
    @discardableResult
    private func spell(_ chunks: [String], live: inout [String]) -> Int {
        let pieces = chunks.map { bubble($0) }
        let points = pieces.map(center)
        let radius = pieces[0].frame.width / 2
        let others = live.filter { !chunks.contains($0) }.map { center(bubble($0)) }

        var strokes: [[CGPoint]] = [[points[0]]]
        for point in points.dropFirst() {
            if legIsClear(strokes[strokes.count - 1].last!, point, others: others + points.filter { $0 != point && $0 != strokes[strokes.count - 1].last! }, radius: radius) {
                strokes[strokes.count - 1].append(point)
            } else {
                strokes.append([point])
            }
        }
        for stroke in strokes {
            if stroke.count == 1 {
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: stroke[0].x, dy: stroke[0].y)).tap()
            } else {
                swipe(through: stroke)
            }
        }
        for chunk in chunks {
            if let index = live.firstIndex(of: chunk) { live.remove(at: index) }
        }
        return strokes.filter { $0.count > 1 }.count
    }

    // MARK: Screenshots

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let env = ProcessInfo.processInfo.environment
        let dir = env["SHOTS_DIR"] ?? (NSTemporaryDirectory() + "shots")
        let device = (env["SIMULATOR_DEVICE_NAME"] ?? "device").replacingOccurrences(of: " ", with: "-")
        let scheme = dark ? "dark" : "light"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(device)-\(scheme)-\(name).png"))
    }

    // MARK: Tests

    func testFinishTutorialByTapping() {
        launch(skipTutorial: false)
        XCTAssertTrue(bubble("RA").waitForExistence(timeout: 10))
        XCTAssertFalse(any("tab-easy").exists, "tutorial hides the tabs")
        XCTAssertFalse(any("days-button").exists, "tutorial hides the calendar")
        XCTAssertFalse(any("hint-button").exists, "tutorial hides the score")
        wait(1)
        shot("tutorial")

        bubble("RA").tap()
        bubble("IN").tap()
        XCTAssertTrue(any("tile-RA").waitForExistence(timeout: 2))
        bubble("BOW").tap()

        XCTAssertTrue(any("result-card").waitForExistence(timeout: 5))
        wait(0.6)
        shot("tutorial-done")
        any("result-primary").tap()
        XCTAssertTrue(any("tab-easy").waitForExistence(timeout: 5))
        XCTAssertTrue(any("hint-button").exists)
    }

    func testTheTutorialCanBeSkipped() {
        launch(skipTutorial: false)
        XCTAssertTrue(any("skip-tutorial").waitForExistence(timeout: 10))
        any("skip-tutorial").tap()
        XCTAssertTrue(any("tab-easy").waitForExistence(timeout: 5))
        XCTAssertFalse(any("skip-tutorial").exists)
    }

    func testPlayAWholeEasyBoardToTheResultCard() {
        launch(skipTutorial: true)
        let puzzle = GameData.shared.puzzle(day: today, level: .easy)
        XCTAssertTrue(bubble(puzzle.chunksByWord[0][0]).waitForExistence(timeout: 10))
        wait(1.2)
        shot("board")

        var live = puzzle.bubbles.map(\.text)
        var swipes = 0
        for (index, chunks) in puzzle.chunksByWord.enumerated() {
            swipes += spell(chunks, live: &live)
            if index == 0 { shot("after-lock") }
            // A prefix of a word can be a bonus word, which takes the tray away. Respell if the word did not lock.
            var tries = 0
            while tries < 3 {
                wait(1.3)
                if any("result-card").exists || any("slot-\(index)").label == puzzle.words[index] { break }
                var again = chunks
                spell(chunks, live: &again)
                tries += 1
            }
        }
        XCTAssertGreaterThan(swipes, 0, "at least one word should have gone in by a swipe")
        XCTAssertTrue(any("result-card").waitForExistence(timeout: 6))
        XCTAssertTrue(any("result-best").exists)
        wait(1.4)
        shot("result")
        XCTAssertEqual(any("result-stars").label.prefix(1) != "0", true)
        XCTAssertTrue(any("result-primary").exists)
    }

    func testSwipeBackUndoesTheLastBubble() {
        launch(skipTutorial: true)
        // Two bubbles that are not a word, picked from different words of a board with no bonus between them.
        let puzzle = GameData.shared.puzzle(day: today, level: .hard)
        any("tab-hard").tap()
        XCTAssertTrue(bubble(puzzle.chunksByWord[0][0]).waitForExistence(timeout: 10))
        wait(1.4)
        let pool = puzzle.bubbles.map(\.text)
        let frames = pool.map { (text: $0, point: center(bubble($0))) }
        let radius = bubble(pool[0]).frame.width / 2

        var pair: (a: CGPoint, b: CGPoint, aText: String, bText: String)?
        search: for first in frames {
            for second in frames where second.text != first.text {
                let others = frames.filter { $0.text != first.text && $0.text != second.text }.map(\.point)
                let bonus = GameData.shared.bonusEntries(day: today, level: .hard).map(\.key)
                if hypot(first.point.x - second.point.x, first.point.y - second.point.y) < radius * 3,
                   legIsClear(first.point, second.point, others: others, radius: radius),
                   !bonus.contains([first.text, second.text].sorted().joined(separator: "|")) {
                    pair = (first.point, second.point, first.text, second.text)
                    break search
                }
            }
        }
        let found = try! XCTUnwrap(pair)
        swipe(through: [found.a, found.b, found.a], secondsPerLeg: 0.4)
        wait(0.6)
        XCTAssertTrue(any("tile-\(found.aText)").exists)
        XCTAssertFalse(any("tile-\(found.bText)").exists, "sliding back removed the last bubble")

        any("tile-\(found.aText)").tap()
        wait(0.5)
        XCTAssertFalse(any("tile-\(found.aText)").exists, "tapping a tile puts it back")

        bubble(found.aText).tap()
        XCTAssertTrue(any("clear-button").waitForExistence(timeout: 2))
        any("clear-button").tap()
        wait(0.5)
        XCTAssertFalse(any("tile-\(found.aText)").exists)
    }

    private func openHelp() {
        any("more-menu").tap()
        XCTAssertTrue(any("help-button").waitForExistence(timeout: 3))
        any("help-button").tap()
        XCTAssertTrue(any("help-close").waitForExistence(timeout: 3))
    }

    func testHelpAndDaysOpenAndClose() {
        launch(skipTutorial: true)
        XCTAssertTrue(any("more-menu").waitForExistence(timeout: 10))

        any("more-menu").tap()
        wait(0.6)
        shot("menu")
        any("help-button").tap()
        XCTAssertTrue(any("help-close").waitForExistence(timeout: 3))
        wait(0.6)
        shot("help")
        any("help-close").tap()
        wait(0.6)
        XCTAssertFalse(any("help-close").exists)

        any("days-button").tap()
        XCTAssertTrue(any("countdown").waitForExistence(timeout: 3))
        XCTAssertTrue(any("day-row-\(today)").waitForExistence(timeout: 3))
        wait(0.6)
        shot("days")
        any("card-close").tap()
        wait(0.6)
        XCTAssertFalse(any("countdown").exists)
    }

    func testDayNavigationAndTabs() {
        launch(skipTutorial: true)
        XCTAssertTrue(any("theme").waitForExistence(timeout: 10))
        wait(0.5)
        any("theme").swipeRight()
        XCTAssertTrue(any("today-button").waitForExistence(timeout: 3), "a sideways swipe on the goal goes back a day")
        wait(0.5)
        shot("earlier-day")
        any("today-button").tap()
        wait(0.5)
        XCTAssertFalse(any("today-button").exists)

        any("days-button").tap()
        XCTAssertTrue(any("day-row-\(today - 1)").waitForExistence(timeout: 3))
        any("day-row-\(today - 1)").tap()
        XCTAssertTrue(any("today-button").waitForExistence(timeout: 3), "the calendar opens the day")
        any("today-button").tap()
        wait(0.5)

        any("tab-medium").tap()
        let theme = GameData.shared.puzzle(day: today, level: .medium).theme
        XCTAssertTrue(any("theme").waitForExistence(timeout: 3))
        XCTAssertEqual(any("theme").label, theme)
    }

    func testHintShuffleAndSpellingStates() {
        launch(skipTutorial: true)
        let puzzle = GameData.shared.puzzle(day: today, level: .easy)
        XCTAssertTrue(any("hint-button").waitForExistence(timeout: 10))
        wait(1.2)
        any("shuffle-button").tap()
        wait(0.6)
        any("hint-button").tap()
        wait(0.5)
        shot("hint-question")
        any("hint-button").tap()
        wait(0.5)
        shot("hinted")
        bubble(puzzle.chunksByWord[1][0]).tap()
        wait(0.6)
        XCTAssertTrue(any("clear-button").exists)
        XCTAssertFalse(any("hint-button").exists, "the tray takes the whole row while spelling")
        shot("spelling")
    }

    /// All orderings of up to three pieces, for turning a bonus key back into a tap order.
    private func orderings(_ pieces: [String]) -> [[String]] {
        guard pieces.count > 1 else { return [pieces] }
        return pieces.indices.flatMap { index -> [[String]] in
            var rest = pieces
            let head = rest.remove(at: index)
            return orderings(rest).map { [head] + $0 }
        }
    }

    func testBonusWordStaysHiddenUntilTheResultAndCombosHeatTheTray() {
        launch(skipTutorial: true)
        let puzzle = GameData.shared.puzzle(day: today, level: .easy)
        let entries = GameData.shared.bonusEntries(day: today, level: .easy)
        let entry = try! XCTUnwrap(entries.first { $0.key.split(separator: "|").count <= 3 })
        let order = try! XCTUnwrap(orderings(entry.key.split(separator: "|").map(String.init)).first { $0.joined() == entry.word })
        XCTAssertTrue(bubble(order[0]).waitForExistence(timeout: 10))
        wait(1.2)

        for piece in order { bubble(piece).tap() }
        wait(0.1)
        shot("bonus-fuse")
        wait(1.1)
        shot("bonus-banked")
        XCTAssertFalse(app.staticTexts[entry.word].exists, "bonus words wait for the score screen")
        XCTAssertFalse(any("clear-button").exists, "a bonus that leads nowhere empties the tray")

        var live = puzzle.bubbles.map(\.text)
        for chunks in puzzle.chunksByWord.prefix(puzzle.words.count - 1) {
            spell(chunks, live: &live)
            wait(1.3)
        }
        XCTAssertTrue(any("combo").waitForExistence(timeout: 3), "two clean words make a combo")
        shot("combo")
    }

    func testDarkModeTour() {
        dark = true
        testFinishTutorialByTapping()
        app.terminate()
        testHintShuffleAndSpellingStates()
        app.terminate()
        testHelpAndDaysOpenAndClose()
        app.terminate()
        testPlayAWholeEasyBoardToTheResultCard()
        app.terminate()
        testBonusWordStaysHiddenUntilTheResultAndCombosHeatTheTray()
    }

    func testLandscapeOnIPad() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPhone is portrait only")
        launch(skipTutorial: true)
        XCTAssertTrue(any("hint-button").waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(1.5)
        shot("landscape")
        XCTAssertTrue(any("hint-button").isHittable)
        XCTAssertTrue(any("tab-hard").isHittable)
        openHelp()
        wait(0.6)
        shot("landscape-help")
    }
}
