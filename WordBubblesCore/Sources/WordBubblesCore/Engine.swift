import Foundation

/// A deterministic port of the web game's engine (`<script id="engine">` in word-bubbles/index.html).
/// The same day and level must produce the same board on both platforms, including draw order.
public enum Engine {
    public static func pickSize<R: RandomSource>(weights: [Int: Double], rng: inout R, max: Int) -> Int {
        var total = 0.0
        for size in stride(from: 1, through: max, by: 1) { total += weights[size] ?? 0 }
        if total <= 0 { return max }
        var remaining = rng.next() * total
        for size in stride(from: 1, through: max, by: 1) {
            remaining -= weights[size] ?? 0
            if remaining <= 0 { return size }
        }
        return max
    }

    /// Cuts a word into 1 to 3 letter chunks; letters keep their order inside each chunk.
    public static func splitWord<R: RandomSource>(_ word: String, weights: [Int: Double], rng: inout R) -> [String] {
        let units = Array(word.utf16)
        var parts: [String] = []
        var pos = 0
        var lastLength = 0
        while pos < units.count {
            let remaining = units.count - pos
            var size = pickSize(weights: weights, rng: &rng, max: min(3, remaining))
            // Never a one-bubble word.
            if parts.isEmpty && size >= units.count { size = max(1, units.count - 1) }
            // No runs of single letters.
            if size == 1 && remaining > 1 && lastLength == 1 { size = 2 }
            parts.append(String(decoding: units[pos..<(pos + size)], as: UTF16.self))
            pos += size
            lastLength = size
        }
        return parts
    }

    /// The distinct multisets of pool chunks that concatenate to `target`, each as sorted chunks joined by "|".
    /// The search stops at two, because callers only ask whether there is exactly one.
    public static func decompositions(of target: String, pool: [String]) -> Set<String> {
        var available: [String: Int] = [:]
        for chunk in pool { available[chunk, default: 0] += 1 }
        let units = Array(target.utf16)
        var list: [String] = []
        var results = Set<String>()

        func search(_ pos: Int) {
            if results.count > 1 { return }
            if pos == units.count {
                results.insert(list.sorted().joined(separator: "|"))
                return
            }
            for length in 1...3 where pos + length <= units.count {
                let chunk = String(decoding: units[pos..<(pos + length)], as: UTF16.self)
                if let left = available[chunk], left > 0 {
                    available[chunk] = left - 1
                    list.append(chunk)
                    search(pos + length)
                    list.removeLast()
                    available[chunk] = left
                }
            }
        }
        search(0)
        return results
    }

    public static func noAdjacentPairs(_ list: [Bubble]) -> Bool {
        for (a, b) in zip(list, list.dropFirst()) where a.wordIndex == b.wordIndex && b.chunkIndex == a.chunkIndex + 1 {
            return false
        }
        return true
    }

    /// Reshuffles until no bubble is followed by its word's next bubble, giving up after 80 rounds, then nudges each.
    public static func shuffleBubbles<R: RandomSource>(_ bubbles: [Bubble], rng: inout R) -> (list: [Bubble], strict: Bool) {
        var list = bubbles
        var strict = false
        var round = 0
        while round < 80 && !strict {
            list = bubbles
            var i = list.count - 1
            while i > 0 {
                let j = Int((rng.next() * Double(i + 1)).rounded(.down))
                list.swapAt(i, j)
                i -= 1
            }
            strict = noAdjacentPairs(list)
            round += 1
        }
        for index in list.indices {
            list[index].nudge = Int(JSMath.round((rng.next() - 0.5) * 10))
        }
        return (list, strict)
    }

    /// `((day * 1000003) + (levelIndex + 1) * 7919) >>> 0`, in doubles as in JS. A level outside
    /// `Level.playable` has index -1.
    static func seedBase(level: Level, day: Int) -> UInt32 {
        let levelIndex = Level.playable.firstIndex(of: level) ?? -1
        return JSMath.toUInt32(Double(day) * 1_000_003 + Double(levelIndex + 1) * 7919)
    }

    /// Builds a board. A board is accepted only when every hidden word can be spelled from the pool in exactly
    /// one way and the shuffle is strict. After 150 seeds, the first board with the best score wins.
    public static func buildPuzzle(level: Level, day: Int, data: PuzzleData) -> Puzzle {
        let weights = level.weights
        let seed = Int(seedBase(level: level, day: day))
        var best: (score: Int, puzzle: Puzzle)?
        for attempt in 0..<150 {
            var rng = Mulberry32(seed: seed + attempt * 101)
            let chunksByWord = data.words.map { splitWord($0, weights: weights, rng: &rng) }
            let pool = chunksByWord.flatMap { $0 }
            let unique = data.words.allSatisfy { decompositions(of: $0, pool: pool).count == 1 }
            var bubbles: [Bubble] = []
            for (wordIndex, parts) in chunksByWord.enumerated() {
                for (chunkIndex, text) in parts.enumerated() {
                    bubbles.append(Bubble(id: "\(wordIndex)-\(chunkIndex)", text: text, wordIndex: wordIndex, chunkIndex: chunkIndex, nudge: 0))
                }
            }
            let shuffled = shuffleBubbles(bubbles, rng: &rng)
            let score = (unique ? 2 : 0) + (shuffled.strict ? 1 : 0)
            if best == nil || score > best!.score {
                best = (score, Puzzle(
                    level: level, theme: data.theme, words: data.words, chunksByWord: chunksByWord,
                    bubbles: shuffled.list, unique: unique, strict: shuffled.strict, attempts: attempt + 1
                ))
            }
            if score == 3 { break }
        }
        return best!.puzzle
    }

    /// The hand-built first board.
    public static func buildTutorial() -> Puzzle {
        let bubble = { (text: String, chunkIndex: Int, nudge: Int) in
            Bubble(id: "0-\(chunkIndex)", text: text, wordIndex: 0, chunkIndex: chunkIndex, nudge: nudge)
        }
        return Puzzle(
            level: .tutorial, theme: "Weather", words: ["RAINBOW"], chunksByWord: [["RA", "IN", "BOW"]],
            bubbles: [bubble("BOW", 2, 4), bubble("RA", 0, -4), bubble("IN", 1, 2)],
            unique: true, strict: true, attempts: nil
        )
    }

    /// Which puzzle a day uses. Puzzles rotate, and this is safe for every `Int`, including days before the epoch.
    public static func puzzleIndex(day: Int, count: Int) -> Int {
        (((day % count) - 1) % count + count) % count
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Midnight UTC on Sep 1 2026, the date of day #1.
    private static let epoch = utcCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!

    /// The calendar a day number is read in: always Gregorian, in the given calendar's time zone, so a device
    /// set to a Buddhist or Japanese calendar still lands on the same day as everyone else.
    private static func gregorian(like calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// The day number of the local calendar date of `date`. Day #1 is Sep 1 2026.
    public static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
        let local = utcCalendar.date(from: parts)!
        return Int((local.timeIntervalSince(epoch) / 86400).rounded(.down)) + 1
    }

    /// Local noon on a day number's date. Noon, because in some zones local midnight can fall in a clock change.
    public static func date(forDay day: Int, calendar: Calendar = .current) -> Date {
        let instant = epoch.addingTimeInterval(Double(day - 1) * 86400)
        var parts = utcCalendar.dateComponents([.year, .month, .day], from: instant)
        parts.hour = 12
        return gregorian(like: calendar).date(from: parts)!
    }
}
