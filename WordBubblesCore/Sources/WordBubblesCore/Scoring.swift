/// How far a score has climbed the star ladder.
public struct Rank: Equatable, Sendable {
    public let stars: Int
    /// Points as a share of the base score.
    public let fraction: Double
    /// Progress from the current star to the next, 0 to 1. Stays 1 at three stars.
    public let toNext: Double
}

/// A rung of the time ladder: a medal, or a record in the end-screen version of the ladder.
public struct Medal: Equatable, Sendable {
    /// "gold", "silver", "bronze", "record", "country" or "local".
    public let key: String
    public let name: String
    public let ms: Int
    public let emoji: String
    /// Set for records, which show this instead of a colored dot.
    public let icon: String?
}

/// What the live medal bar shows.
public struct ClockState: Equatable, Sendable {
    /// The medal whose window the time is in. Nil past bronze or after a hint.
    public let medal: Medal?
    /// How much of that window is left, 0 to 1.
    public let fractionLeft: Double
    public let timeText: String
    public let accessibilityLabel: String
}

/// Points only ever go up. A hidden word is 10 per letter × combo (×1…×4), a bonus word 5 per letter,
/// a secret 25 per letter, and a word finished by hints 5 per letter.
public enum Scoring {
    /// Stars are measured against the board's base score of 10 per letter: 1★ at half of it, 2★ at all of it,
    /// 3★ at 1.5×.
    public static let starAt = [0.5, 1.0, 1.5]

    public static func multiplier(_ combo: Int) -> Int {
        min(max(combo, 1), 4)
    }

    public static func maxPoints(_ puzzle: Puzzle) -> Int {
        puzzle.words.reduce(0) { $0 + $1.count * 10 }
    }

    public static func rank(points: Int, puzzle: Puzzle, finished: Bool = false) -> Rank {
        let fraction = Double(points) / Double(max(1, maxPoints(puzzle)))
        var stars = starAt.filter { fraction >= $0 }.count
        if finished { stars = max(1, stars) }
        guard stars < starAt.count else { return Rank(stars: stars, fraction: fraction, toNext: 1) }
        let low = stars > 0 ? starAt[stars - 1] : 0
        let toNext = max(0, min(1, (fraction - low) / (starAt[stars] - low)))
        return Rank(stars: stars, fraction: fraction, toNext: toNext)
    }

    public static func starText(_ stars: Int) -> String {
        String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars)
    }

    public static func heat(_ combo: Int) -> Int {
        combo >= 5 ? 3 : combo >= 3 ? 2 : combo >= 2 ? 1 : 0
    }

    /// Gold 3s, silver 5s, bronze 8s per bubble, counting every bubble on the full board.
    public static func medalTimes(bubbleCount n: Int) -> [Medal] {
        [
            Medal(key: "gold", name: "Gold", ms: n * 3000, emoji: "🥇", icon: nil),
            Medal(key: "silver", name: "Silver", ms: n * 5000, emoji: "🥈", icon: nil),
            Medal(key: "bronze", name: "Bronze", ms: n * 8000, emoji: "🥉", icon: nil),
        ]
    }

    /// `medalTimes` with any records that beat gold on top. A narrower record only shows when it is slower than
    /// the broader one above it.
    public static func medalLadder(
        day: Int, level: Level, bubbleCount: Int, records: [String: RecordEntry], place: Place
    ) -> [Medal] {
        let medals = medalTimes(bubbleCount: bubbleCount)
        let gold = medals[0].ms
        var top: [Medal] = []
        var faster = 0
        for key in place.recordKeys(day: day, level: level) {
            guard let ms = records[key.id]?.ms, ms > 0, ms < gold, ms > faster else { continue }
            let rung = recordRung(tier: key.tier, ms: ms, place: place)
            top.append(rung)
            faster = ms
        }
        return top + medals
    }

    private static func recordRung(tier: RecordTier, ms: Int, place: Place) -> Medal {
        switch tier {
        case .world:
            return Medal(key: "record", name: "World record", ms: ms, emoji: "👑", icon: "👑")
        case .country:
            let flag = place.country?.flag ?? ""
            return Medal(key: "country", name: (place.country?.name ?? "") + " record", ms: ms, emoji: flag, icon: flag)
        case .local:
            return Medal(key: "local", name: (place.local?.name ?? "") + " record", ms: ms, emoji: "📍", icon: "📍")
        }
    }

    /// The best rung this time reached, for the share text. Sees records too, and compares the unrounded time.
    public static func medalFor(
        ms: Double, day: Int, level: Level, bubbleCount: Int, progress: LevelProgress,
        records: [String: RecordEntry], place: Place
    ) -> Medal? {
        guard ms != 0, !progress.forfeitedMedal else { return nil }
        return medalLadder(day: day, level: level, bubbleCount: bubbleCount, records: records, place: place)
            .first { ms <= Double($0.ms) }
    }

    /// The medal bar drains through the current medal's window, then turns to the next medal and refills.
    public static func clock(elapsedMs ms: Double, forfeited: Bool, bubbleCount: Int) -> ClockState {
        let times = medalTimes(bubbleCount: bubbleCount)
        let index = forfeited ? nil : times.firstIndex { ms <= Double($0.ms) }
        let timeText = GameText.time(ms: ms)
        guard let index else {
            return ClockState(medal: nil, fractionLeft: 0, timeText: timeText, accessibilityLabel: "No medal, " + timeText)
        }
        let medal = times[index]
        let start = index > 0 ? times[index - 1].ms : 0
        let left = (Double(medal.ms) - ms) / Double(medal.ms - start)
        let remaining = GameText.time(ms: Double(medal.ms) - ms)
        return ClockState(
            medal: medal, fractionLeft: max(0, min(1, left)), timeText: timeText,
            accessibilityLabel: medal.name + ", " + remaining + " left, " + timeText
        )
    }
}
