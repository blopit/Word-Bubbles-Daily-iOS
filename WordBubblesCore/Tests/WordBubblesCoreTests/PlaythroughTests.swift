import XCTest
@testable import WordBubblesCore

final class PlaythroughTests: XCTestCase {
    let days = [1, 2, 3, 17, 42, 64, 100, 200, 201, 365, 1000]

    /// Hidden-word points for a clean run: 10 a letter × combo capped at 4.
    func cleanPoints(_ puzzle: Puzzle) -> Int {
        puzzle.words.enumerated().reduce(0) { total, item in
            total + item.element.count * 10 * min(item.offset + 1, 4)
        }
    }

    func bonusPoints(_ session: GameSession) -> Int {
        session.progress.bonus.reduce(0) { total, word in
            total + word.count * (GameData.shared.isSecret(word: word, theme: session.puzzle.theme) ? 25 : 5)
        }
    }

    func testCleanRunsOnRealBoardsScoreExactly() {
        for day in days {
            for level in Level.playable {
                var s = realSession(day: day, level: level)
                let events = s.solveAll()
                XCTAssertTrue(s.progress.done, "\(day) \(level)")
                XCTAssertEqual(s.combo, s.puzzle.words.count, "\(day) \(level)")
                XCTAssertEqual(s.progress.points - bonusPoints(s), cleanPoints(s.puzzle), "\(day) \(level)")
                XCTAssertEqual(events.filter { $0 == .finished }.count, 1, "\(day) \(level)")
                XCTAssertEqual(Set(s.progress.consumed).count, s.puzzle.bubbles.count)
                XCTAssertEqual(Set(s.progress.found), Set(s.puzzle.words.indices))
                XCTAssertGreaterThanOrEqual(s.rank.stars, 2, "a clean finish is at least 2★")
            }
        }
    }

    func testHintsAloneFinishEveryBoard() {
        for day in days {
            for level in Level.playable {
                var s = realSession(day: day, level: level)
                var guardCount = 0
                while !s.progress.done && guardCount < 200 {
                    s.hint()
                    guardCount += 1
                }
                XCTAssertTrue(s.progress.done, "\(day) \(level)")
                XCTAssertEqual(s.progress.points, s.puzzle.words.reduce(0) { $0 + $1.count * 5 })
                XCTAssertEqual(s.rank.stars, 1, "half the base score")
                XCTAssertTrue(s.progress.forfeitedMedal)
            }
        }
    }

    func testPlayingAcrossDaysThroughSwipes() {
        let store = ProgressStore(url: tempStoreURL(), today: 9)
        var swipe = SwipeTracker()
        for level in Level.playable {
            var s = realSession(day: 9, level: level, store: store)
            for wordIndex in s.puzzle.words.indices {
                while !s.progress.found.contains(wordIndex) {
                    swipe.pointerDown(hit: "\(wordIndex)-0", session: &s)
                    for chunk in s.puzzle.chunksByWord[wordIndex].indices.dropFirst() {
                        swipe.pointerMove(hit: "\(wordIndex)-\(chunk)", session: &s)
                    }
                    swipe.pointerUp(session: s)
                    if !s.progress.found.contains(wordIndex) { s.clearChain() }
                }
            }
            XCTAssertTrue(s.progress.done)
        }
        XCTAssertEqual(store.stats.days, 1)
    }
}

/// Random legal play, on real boards: nothing crashes, points never drop, and the board can always be finished.
final class RandomPlayPropertyTests: XCTestCase {
    private func draw(_ rng: inout Mulberry32, _ count: Int) -> Int {
        Int(rng.next() * Double(count))
    }

    private func randomStep(_ s: inout GameSession, swipe: inout SwipeTracker, rng: inout Mulberry32) {
        let live = s.liveBubbles.map(\.id)
        switch draw(&rng, 20) {
        case 0..<9:
            if !live.isEmpty { s.addToChain(live[draw(&rng, live.count)]) }
        case 9..<11:
            if !s.chain.isEmpty { s.removeFromChain(s.chain[draw(&rng, s.chain.count)]) }
        case 11:
            s.clearChain()
        case 12:
            s.hint()
        case 13:
            var copy = rng
            s.shuffle(rng: &copy)
            rng = copy
        case 14:
            s.pause()
            s.resume()
        case 15:
            if let button = s.bonusButton { s.collectBonus(button.word) }
        case 16:
            swipe.pointerDown(hit: live.isEmpty ? nil : live[draw(&rng, live.count)], session: &s)
        case 17:
            swipe.pointerMove(hit: live.isEmpty ? nil : live[draw(&rng, live.count)], session: &s)
        case 18:
            swipe.pointerUp(session: s)
        default:
            // Spell a hidden word's chunks, to reach locks often.
            if let index = s.puzzle.words.indices.first(where: { !s.progress.found.contains($0) }) {
                for chunk in s.puzzle.chunksByWord[index].indices { s.addToChain("\(index)-\(chunk)") }
            }
        }
    }

    private func checkInvariants(_ s: GameSession, _ before: LevelProgress, _ label: String) {
        let p = s.progress
        XCTAssertGreaterThanOrEqual(p.points, before.points, label)
        XCTAssertGreaterThanOrEqual(p.moves, before.moves, label)
        XCTAssertGreaterThanOrEqual(p.bestCombo, before.bestCombo, label)
        XCTAssertGreaterThanOrEqual(p.elapsed, before.elapsed, label)
        XCTAssertEqual(Set(p.consumed).count, p.consumed.count, label)
        XCTAssertEqual(Set(p.found).count, p.found.count, label)
        XCTAssertEqual(Set(s.chain).count, s.chain.count, label)
        XCTAssertTrue(Set(s.chain).isDisjoint(with: p.consumed), label)
        XCTAssertTrue(Set(s.order).isSubset(of: Set(s.puzzle.bubbles.map(\.id))), label)
        XCTAssertLessThanOrEqual(s.rank.toNext, 1, label)
        XCTAssertEqual(p.done, p.found.count == s.puzzle.words.count, label)
    }

    /// Finishes by spelling what is left, falling back to hints. Bubbles may have swapped between same-text twins.
    private func finish(_ s: inout GameSession, _ label: String) {
        s.clearChain()
        var attempts = 0
        while !s.progress.done && attempts < 300 {
            attempts += 1
            guard let index = s.puzzle.words.indices.first(where: { !s.progress.found.contains($0) }) else { break }
            for text in s.puzzle.chunksByWord[index] {
                let bubble = s.liveBubbles.first { $0.text == text && !s.chain.contains($0.id) }
                if let bubble { s.addToChain(bubble.id) }
                if s.chain.isEmpty { break }
            }
            if !s.progress.found.contains(index) {
                s.clearChain()
                if attempts > 20 { s.hint() }
            }
        }
        XCTAssertTrue(s.progress.done, label)
    }

    func testRandomPlay() {
        var seed = 11
        for day in stride(from: 1, through: 240, by: 7) {
            for level in Level.playable {
                seed += 1
                var rng = Mulberry32(seed: seed)
                let clock = FakeClock()
                let store = ProgressStore(url: tempStoreURL(), today: day)
                var s = GameSession(day: day, level: level, store: store, now: clock.now)
                var swipe = SwipeTracker()
                let label = "\(day) \(level) seed \(seed)"
                for _ in 0..<160 {
                    let before = s.progress
                    clock.advance(ms: rng.next() * 3000)
                    randomStep(&s, swipe: &swipe, rng: &rng)
                    checkInvariants(s, before, label)
                }
                let before = s.progress
                if !s.progress.done { finish(&s, label) }
                checkInvariants(s, before, label)
                XCTAssertEqual(store.record(day: day, level: level).done, true, label)
                XCTAssertEqual(s.hint(), [], label)
                XCTAssertEqual(s.shuffle(), [], label)
                _ = ResultCard.make(
                    day: day, level: level, store: store, place: .nowhere, records: nil,
                    formatter: DayFormatter(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
                )
            }
        }
    }
}
