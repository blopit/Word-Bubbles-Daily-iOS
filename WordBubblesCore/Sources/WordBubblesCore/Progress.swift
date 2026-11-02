/// Which narrower record a finish took, when it was not the world record.
public enum RegionalTier: String, Codable, Hashable, Sendable {
    case country, local
}

/// One board's saved state: the web game's `freshProgress` plus the fields it adds as you play.
public struct LevelProgress: Codable, Equatable, Sendable {
    public var found: [Int] = []
    public var consumed: [String] = []
    public var moves = 0
    public var hints: [Int: Int] = [:]
    public var done = false
    public var points = 0
    public var bestCombo = 0
    public var bonus: [String] = []
    /// Milliseconds.
    public var elapsed = 0.0
    public var usedHint = false
    public var newRecord = false
    public var newRegional: RegionalTier?

    public init() {}

    /// A record with no `found` list is discarded, as `recFor` does. Any other bad or missing field takes its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let found = try? c.decode([Int].self, forKey: .found) else { return }
        self.found = found
        consumed = (try? c.decode([String].self, forKey: .consumed)) ?? []
        moves = (try? c.decode(Int.self, forKey: .moves)) ?? 0
        hints = (try? c.decode([Int: Int].self, forKey: .hints)) ?? [:]
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        points = (try? c.decode(Int.self, forKey: .points)) ?? 0
        bestCombo = (try? c.decode(Int.self, forKey: .bestCombo)) ?? 0
        bonus = (try? c.decode([String].self, forKey: .bonus)) ?? []
        elapsed = (try? c.decode(Double.self, forKey: .elapsed)) ?? 0
        usedHint = (try? c.decode(Bool.self, forKey: .usedHint)) ?? false
        newRecord = (try? c.decode(Bool.self, forKey: .newRecord)) ?? false
        newRegional = try? c.decode(RegionalTier.self, forKey: .newRegional)
    }

    /// A hint sticks for the whole board: solved words drop their hint marks, so the flag has to outlive them.
    public var forfeitedMedal: Bool {
        usedHint || hints.values.contains { $0 > 0 }
    }
}

/// Lifetime totals. Only finishing all three of today's boards counts.
public struct Stats: Codable, Equatable, Sendable {
    public var days = 0
    public var streak = 0
    public var best = 0
    public var perfect = 0
    public var lastDay: Int?

    public init(days: Int = 0, streak: Int = 0, best: Int = 0, perfect: Int = 0, lastDay: Int? = nil) {
        self.days = days
        self.streak = streak
        self.best = best
        self.perfect = perfect
        self.lastDay = lastDay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? c.decode(Int.self, forKey: .days)) ?? 0
        streak = (try? c.decode(Int.self, forKey: .streak)) ?? 0
        best = (try? c.decode(Int.self, forKey: .best)) ?? 0
        perfect = (try? c.decode(Int.self, forKey: .perfect)) ?? 0
        lastDay = try? c.decode(Int.self, forKey: .lastDay)
    }

    /// `updateStats`: counts a day once. `perfect` means three stars on all three boards.
    public mutating func record(day: Int, perfect isPerfect: Bool) {
        if lastDay == day { return }
        days += 1
        streak = lastDay == day - 1 ? streak + 1 : 1
        best = max(best, streak)
        lastDay = day
        if isPerfect { perfect += 1 }
    }
}
