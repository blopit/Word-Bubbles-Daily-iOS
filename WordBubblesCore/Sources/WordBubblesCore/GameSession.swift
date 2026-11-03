import Foundation

/// A draw of `Double.random` for the free shuffle.
public struct SystemRandomSource: RandomSource {
    public init() {}
    public mutating func next() -> Double { Double.random(in: 0..<1) }
}

/// One slot in the row of hidden words.
public enum WordSlot: Equatable, Sendable {
    case solved(String)
    /// The revealed pieces, such as "TO·AS·…".
    case hinted(String)
    case hidden(letters: Int)
}

/// The bonus button's state. Shown only when the tray spells a bonus word not yet collected.
public struct BonusButton: Equatable, Sendable {
    public let word: String
    public let isSecret: Bool
    /// "✦ Bonus" or "◆ Secret".
    public let label: String
}

public struct BonusChip: Equatable, Sendable {
    public let word: String
    public let isSecret: Bool
}

/// One board in play. A value type, so a UI can keep it in an `@Observable` model and see every mutation.
///
/// All rules live here. State changes synchronously and mutators return what happened; the web game's `busy` window
/// is the UI's to enforce by blocking input while it animates. Opening a board means making a new session, which
/// resets the combo and restores the full bubble order. Tutorial progress is never saved.
public struct GameSession {
    private static let maxTickMs = 10.0 * 60 * 1000

    public let day: Int
    public let level: Level
    public let puzzle: Puzzle
    public private(set) var progress: LevelProgress
    /// Picked bubble ids, in the order they were picked.
    public private(set) var chain: [String] = []
    /// Bubble ids in honeycomb order. Changes only on shuffle, and only then drops consumed bubbles.
    public private(set) var order: [String]
    public private(set) var combo = 0
    /// False once the run is broken, until the next word locks.
    public private(set) var clean = true

    private let store: ProgressStore
    private let bonusEntries: [(key: String, word: String)]
    private let bonusWords: Set<String>
    private let isSecret: (String) -> Bool
    private let puzzleFor: (Level) -> Puzzle
    private let now: () -> Date
    private let bubbles: [String: Bubble]
    private var startedAt: Date?
    private var lastStars: Int

    public init(day: Int, level: Level, store: ProgressStore, data: GameData = .shared, now: @escaping () -> Date = Date.init) {
        let puzzle = data.puzzle(day: day, level: level)
        self.init(
            day: day, level: level, puzzle: puzzle, bonus: data.bonusEntries(day: day, level: level),
            isSecret: { data.isSecret(word: $0, theme: puzzle.theme) }, store: store,
            puzzleFor: { data.puzzle(day: day, level: $0) }, now: now
        )
    }

    /// For tests, which supply their own board.
    init(
        day: Int, level: Level, puzzle: Puzzle, bonus: [(key: String, word: String)], isSecret: @escaping (String) -> Bool,
        store: ProgressStore, puzzleFor: @escaping (Level) -> Puzzle, now: @escaping () -> Date
    ) {
        self.day = day
        self.level = level
        self.puzzle = puzzle
        self.store = store
        self.bonusEntries = level == .tutorial ? [] : bonus
        // `bonusMap`: one word per key, the last one in the file.
        var byKey: [String: String] = [:]
        for entry in bonusEntries { byKey[entry.key] = entry.word }
        self.bonusWords = Set(byKey.values)
        self.isSecret = isSecret
        self.puzzleFor = puzzleFor
        self.now = now
        self.bubbles = Dictionary(uniqueKeysWithValues: puzzle.bubbles.map { ($0.id, $0) })
        let saved = level == .tutorial ? LevelProgress() : store.record(day: day, level: level)
        self.progress = saved
        self.order = puzzle.bubbles.map(\.id)
        self.lastStars = Scoring.rank(points: saved.points, puzzle: puzzle).stars
        if level != .tutorial && !saved.done { startedAt = now() }
    }

    // MARK: - Reading

    public var isTutorial: Bool { level == .tutorial }

    public func bubble(id: String) -> Bubble? { bubbles[id] }

    /// Bubbles still on the board, in `puzzle.bubbles` order.
    public var liveBubbles: [Bubble] {
        let gone = consumed
        return puzzle.bubbles.filter { !gone.contains($0.id) }
    }

    public var consumed: Set<String> { Set(progress.consumed) }

    public var rank: Rank { Scoring.rank(points: progress.points, puzzle: puzzle, finished: progress.done) }

    /// What the tray spells.
    public var spelled: String { chain.compactMap { bubbles[$0]?.text }.joined() }

    public var letterCount: Int { spelled.count }
    public var letterCountText: String { GameText.letterCount(letterCount) }
    public var prompt: String { GameText.prompt(level: level) }

    /// The combo badge, shown from ×2. Not capped, unlike the score multiplier.
    public var comboText: String? { combo >= 2 ? "×\(combo)" : nil }
    public var heat: Int { Scoring.heat(combo) }

    public var scoreAccessibilityLabel: String { "\(rank.stars) of 3 stars, \(progress.points) points" }

    /// The time so far in milliseconds, including the running tick.
    public var liveElapsed: Double { progress.elapsed + runningTick }

    /// The medal bar. Nil in the tutorial.
    public var clock: ClockState? {
        guard !isTutorial else { return nil }
        return Scoring.clock(elapsedMs: liveElapsed, forfeited: progress.forfeitedMedal, bubbleCount: puzzle.bubbles.count)
    }

    public var slots: [WordSlot] {
        puzzle.words.indices.map { index in
            if progress.found.contains(index) { return .solved(puzzle.words[index]) }
            let hinted = progress.hints[index] ?? 0
            if hinted > 0 {
                return .hinted(puzzle.chunksByWord[index].prefix(hinted).joined(separator: "·") + "·…")
            }
            return .hidden(letters: puzzle.words[index].count)
        }
    }

    /// Bubbles marked by hints: id to piece number, starting at 1.
    public var hintTargets: [String: Int] {
        var targets: [String: Int] = [:]
        for index in puzzle.words.indices where !progress.found.contains(index) {
            let level = progress.hints[index] ?? 0
            var used = Set<String>()
            for chunk in 0..<min(level, puzzle.chunksByWord[index].count) {
                if let id = findBubble(wordIndex: index, chunkIndex: chunk, used: used) {
                    used.insert(id)
                    targets[id] = chunk + 1
                }
            }
        }
        return targets
    }

    public var bonusButton: BonusButton? {
        guard let word = bonusMatch, !progress.bonus.contains(word) else { return nil }
        let secret = isSecret(word)
        return BonusButton(word: word, isSecret: secret, label: secret ? "◆ Secret" : "✦ Bonus")
    }

    /// The bonus words found, newest first. Nil while the bar is hidden.
    public var bonusBar: [BonusChip]? {
        guard !isTutorial, !bonusEntries.isEmpty, !progress.bonus.isEmpty else { return nil }
        return progress.bonus.reversed().map { BonusChip(word: $0, isSecret: isSecret($0)) }
    }

    /// How many more bonus words can be made from the bubbles left.
    public var bonusStillPossible: Int {
        let have = Set(progress.bonus)
        var pool: [String: Int] = [:]
        for bubble in liveBubbles { pool[bubble.text, default: 0] += 1 }
        var words = Set<String>()
        for entry in bonusEntries where !have.contains(entry.word) && !words.contains(entry.word) {
            var need: [Substring: Int] = [:]
            let fits = entry.key.split(separator: "|").allSatisfy { chunk in
                need[chunk, default: 0] += 1
                return need[chunk, default: 0] <= pool[String(chunk), default: 0]
            }
            if fits { words.insert(entry.word) }
        }
        return words.count
    }

    /// The finished board to post to the records server. Nil unless it is done, daily and medal-eligible.
    public var finishedBoard: FinishedBoard? {
        guard progress.done, !isTutorial, !progress.forfeitedMedal else { return nil }
        return FinishedBoard(day: day, level: level, progress: progress, bubbleCount: puzzle.bubbles.count)
    }

    // MARK: - The chain

    /// Rejects a bubble already picked, already consumed or not on this board by returning no events.
    @discardableResult
    public mutating func addToChain(_ id: String) -> [GameEvent] {
        guard !chain.contains(id), !progress.consumed.contains(id), bubbles[id] != nil else { return [] }
        chain.append(id)
        if !isTutorial {
            progress.moves += 1
            save(persist: false)
        }
        return [.picked(id: id, chainLength: chain.count, combo: combo)] + checkChain().events
    }

    /// Puts a bubble back. The chain is checked again, because what's left may spell something. If it doesn't,
    /// the combo breaks.
    @discardableResult
    public mutating func removeFromChain(_ id: String) -> [GameEvent] {
        guard let index = chain.firstIndex(of: id) else { return [] }
        chain.remove(at: index)
        let check = checkChain()
        if check.completed { return check.events }
        return check.events + [.unpicked(ids: [id])] + breakCombo()
    }

    @discardableResult
    public mutating func clearChain() -> [GameEvent] {
        guard !chain.isEmpty else { return [] }
        let ids = chain
        chain = []
        return [.unpicked(ids: ids)] + breakCombo()
    }

    /// Collects the word on the bonus button. The bubbles stay in play, the combo is untouched and the tray empties.
    @discardableResult
    public mutating func collectBonus(_ word: String) -> [GameEvent] {
        guard bonusWords.contains(word), !progress.bonus.contains(word) else { return [] }
        progress.bonus.append(word)
        let secret = isSecret(word)
        let points = word.count * (secret ? 25 : 5)
        progress.points += points
        save()
        let ids = chain
        chain = []
        return starEvents() + [.bonusCollected(word: word, isSecret: secret, points: points, ids: ids)]
    }

    /// Banks a bonus word without touching the tray. Unlike the website, which empties the tray here and makes the
    /// player spell their hidden word again.
    private mutating func collectBonusInline(_ word: String) -> [GameEvent] {
        progress.bonus.append(word)
        let secret = isSecret(word)
        let points = word.count * (secret ? 25 : 5)
        progress.points += points
        save()
        return starEvents() + [.bonusInline(word: word, isSecret: secret, points: points)]
    }

    /// True when the tiles so far are the start of a hidden word still to find.
    private var startsHiddenWord: Bool {
        let text = spelled
        return puzzle.words.indices.contains { index in
            !progress.found.contains(index) && puzzle.words[index].hasPrefix(text) && puzzle.words[index] != text
        }
    }

    /// The same check after a bubble is added or put back: hidden word, then new bonus, then found bonus, then cues.
    private mutating func checkChain() -> (completed: Bool, events: [GameEvent]) {
        if let index = matchWord { return (true, lockWord(index)) }
        if let word = bonusMatch {
            if progress.bonus.contains(word) { return (true, [.bonusAlreadyFound(word: word)]) }
            return (true, startsHiddenWord ? collectBonusInline(word) : collectBonus(word))
        }
        return (false, lengthCue())
    }

    /// Which unfound word do the picked bubbles spell?
    private var matchWord: Int? {
        guard !chain.isEmpty else { return nil }
        let text = spelled
        return puzzle.words.indices.first { !progress.found.contains($0) && puzzle.words[$0] == text }
    }

    private var bonusMatch: String? {
        guard chain.count >= 2 else { return nil }
        let text = spelled
        return bonusWords.contains(text) ? text : nil
    }

    private var rightPiecesWrongOrder: Bool {
        guard chain.count >= 2 else { return false }
        let key = chain.compactMap { bubbles[$0]?.text }.sorted()
        return puzzle.words.indices.contains { !progress.found.contains($0) && puzzle.chunksByWord[$0].sorted() == key }
    }

    private func lengthCue() -> [GameEvent] {
        let lengths = puzzle.words.indices.filter { !progress.found.contains($0) }.map { puzzle.words[$0].count }
        guard let longest = lengths.max() else { return [] }
        if rightPiecesWrongOrder { return [.nearMiss(isTutorial: isTutorial)] }
        return letterCount > longest ? [.tooManyLetters] : []
    }

    private mutating func lockWord(_ index: Int) -> [GameEvent] {
        let ids = chain
        chain = []
        progress.found.append(index)
        progress.consumed += ids
        progress.hints[index] = nil
        combo = clean ? combo + 1 : 1
        clean = true
        let word = puzzle.words[index]
        var gained = 0
        if !isTutorial {
            gained = word.count * 10 * Scoring.multiplier(combo)
            progress.bestCombo = max(progress.bestCombo, combo)
            progress.points += gained
        }
        save()
        let completes = progress.found.count == puzzle.words.count
        let locked = GameEvent.wordLocked(
            wordIndex: index, word: word, ids: ids, gained: gained, combo: combo, isTutorial: isTutorial, completesBoard: completes
        )
        return starEvents() + [locked] + (completes ? finish() : [])
    }

    private mutating func breakCombo() -> [GameEvent] {
        guard !isTutorial else { return [] }
        let wasCombo = combo >= 2
        clean = false
        combo = 0
        return [.comboBroken(wasCombo: wasCombo)]
    }

    private mutating func starEvents() -> [GameEvent] {
        guard !isTutorial else { return [] }
        let stars = Scoring.rank(points: progress.points, puzzle: puzzle).stars
        defer { lastStars = stars }
        return stars > lastStars ? [.starEarned(stars: stars)] : []
    }

    // MARK: - Hints

    private func findBubble(wordIndex: Int, chunkIndex: Int, used: Set<String>) -> String? {
        let text = puzzle.chunksByWord[wordIndex][chunkIndex]
        let free = { (id: String) in !progress.consumed.contains(id) && !used.contains(id) }
        let own = "\(wordIndex)-\(chunkIndex)"
        if bubbles[own] != nil && free(own) { return own }
        return puzzle.bubbles.first { $0.text == text && free($0.id) }?.id
    }

    private func pickIds(forWord index: Int) -> [String] {
        var used = Set<String>()
        var ids: [String] = []
        for chunk in puzzle.chunksByWord[index].indices {
            if let id = findBubble(wordIndex: index, chunkIndex: chunk, used: used) {
                used.insert(id)
                ids.append(id)
            }
        }
        return ids
    }

    /// Reveals the next piece of the first hinted word, else of the first unfound word. Costs the combo and the
    /// medal. A word with every piece revealed locks on its own for 5 points a letter.
    @discardableResult
    public mutating func hint() -> [GameEvent] {
        guard !progress.done, !isTutorial else { return [] }
        let unfound = puzzle.words.indices.filter { !progress.found.contains($0) }
        guard let index = unfound.first(where: { (progress.hints[$0] ?? 0) > 0 }) ?? unfound.first else { return [] }
        let chunks = puzzle.chunksByWord[index]
        let shown = (progress.hints[index] ?? 0) + 1
        let firstHint = !progress.forfeitedMedal
        progress.usedHint = true
        progress.hints[index] = shown
        var events = breakCombo()
        guard shown >= chunks.count else {
            save()
            return events + [.hintRevealed(wordIndex: index, chunks: Array(chunks.prefix(shown)), firstHint: firstHint)]
        }
        let ids = pickIds(forWord: index)
        chain.removeAll { ids.contains($0) }
        progress.found.append(index)
        progress.consumed += ids
        progress.hints[index] = nil
        let word = puzzle.words[index]
        let points = word.count * 5
        progress.points += points
        save()
        events += starEvents()
        events.append(.wordRevealed(wordIndex: index, word: word, ids: ids, points: points, firstHint: firstHint))
        if progress.found.count == puzzle.words.count { events += finish() }
        return events
    }

    // MARK: - The board

    /// Re-deals the bubbles left into a fresh honeycomb. Free.
    @discardableResult
    public mutating func shuffle<R: RandomSource>(rng: inout R) -> [GameEvent] {
        guard !progress.done else { return [] }
        var ids = liveBubbles.map(\.id)
        var i = ids.count - 1
        while i > 0 {
            ids.swapAt(i, Int((rng.next() * Double(i + 1)).rounded(.down)))
            i -= 1
        }
        order = ids
        return [.shuffled]
    }

    @discardableResult
    public mutating func shuffle() -> [GameEvent] {
        var rng = SystemRandomSource()
        return shuffle(rng: &rng)
    }

    /// Wipes this board and starts it again. Stats already earned stay.
    public mutating func replay() {
        progress = LevelProgress()
        save()
        tick()
        store.saveNow()
        chain = []
        order = puzzle.bubbles.map(\.id)
        combo = 0
        clean = true
        lastStars = 0
        startedAt = isTutorial ? nil : now()
    }

    private mutating func finish() -> [GameEvent] {
        tick()
        startedAt = nil
        progress.done = true
        if isTutorial {
            store.setTutorialDone()
            return [.finished]
        }
        save()
        if day == store.today && Level.playable.allSatisfy({ store.isDone(day: day, level: $0) }) {
            var stats = store.stats
            stats.record(day: day, perfect: isPerfectDay)
            store.setStats(stats)
        }
        return [.finished]
    }

    private var isPerfectDay: Bool {
        Level.playable.allSatisfy { level in
            let points = store.record(day: day, level: level).points
            return Scoring.rank(points: points, puzzle: puzzleFor(level), finished: true).stars == 3
        }
    }

    // MARK: - Time

    private var runningTick: Double {
        guard let startedAt else { return 0 }
        return min(now().timeIntervalSince(startedAt) * 1000, Self.maxTickMs)
    }

    private mutating func tick() {
        guard startedAt != nil else { return }
        progress.elapsed += runningTick
        startedAt = now()
    }

    /// Stops the clock and saves. Call when the app leaves the foreground.
    public mutating func pause() {
        stopClock()
    }

    /// Restarts the clock. Call when the app returns. Does nothing while it is running or after the finish.
    public mutating func resume() {
        guard startedAt == nil, !progress.done, !isTutorial else { return }
        startedAt = now()
    }

    /// Call before moving to another board.
    public mutating func leave() {
        stopClock()
        chain = []
    }

    /// Writes unsaved picks, like the web game does when a finger lifts.
    public func saveNow() {
        store.saveNow()
    }

    private mutating func stopClock() {
        if startedAt != nil {
            tick()
            startedAt = nil
            save(persist: false)
        }
        store.saveNow()
    }

    private func save(persist: Bool = true) {
        guard !isTutorial else { return }
        store.setRecord(progress, day: day, level: level, persist: persist)
    }
}
