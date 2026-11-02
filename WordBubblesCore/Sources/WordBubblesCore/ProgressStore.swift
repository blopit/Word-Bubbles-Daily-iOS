import Foundation

/// A row of the "Your days" list.
public struct DayRow: Equatable, Sendable {
    public let day: Int
    /// The levels finished that day, in play order.
    public let done: [Level]
    /// "Play" while any board is open, else "Open".
    public let buttonLabel: String
}

/// All saved games: one record per day and level, plus stats and the tutorial flag.
/// Kept in a JSON file that is replaced atomically. A missing or corrupt file gives an empty store.
/// Not thread-safe: use it from one actor, normally the main one.
public final class ProgressStore {
    /// How far back the archive goes.
    public static let keepDays = 400

    public private(set) var today: Int
    public private(set) var stats = Stats()
    public private(set) var tutorialDone = false

    private let url: URL
    private var days: [Int: [Level: LevelProgress]] = [:]
    private var dirty = false

    public init(url: URL, today: Int) {
        self.url = url
        self.today = today
        load()
        prune()
    }

    /// Call when the calendar day changes.
    public func rollover(today: Int) {
        self.today = today
        prune()
    }

    public func record(day: Int, level: Level) -> LevelProgress {
        days[day]?[level] ?? LevelProgress()
    }

    /// `persist: false` keeps the change in memory until the next `saveNow` or persisting write,
    /// like the web game's delayed `persistSoon`.
    public func setRecord(_ progress: LevelProgress, day: Int, level: Level, persist: Bool = true) {
        days[day, default: [:]][level] = progress
        dirty = true
        if persist { saveNow() }
    }

    public func setStats(_ stats: Stats) {
        self.stats = stats
        dirty = true
        saveNow()
    }

    public func setTutorialDone() {
        tutorialDone = true
        dirty = true
        saveNow()
    }

    public func isDone(day: Int, level: Level) -> Bool {
        days[day]?[level]?.done ?? false
    }

    public func firstOpenLevel(day: Int) -> Level {
        Level.playable.first { !isDone(day: day, level: $0) } ?? .hard
    }

    /// The board to show first: the tutorial on today's first visit, else the day's first open board.
    public func initialLevel(day: Int) -> Level {
        !tutorialDone && day == today ? .tutorial : firstOpenLevel(day: day)
    }

    /// The board to show after moving to another day: the same difficulty, or the first open one after the tutorial.
    public func level(forDay day: Int, stayingOn current: Level) -> Level {
        Level.playable.contains(current) ? current : firstOpenLevel(day: day)
    }

    /// The most recent day in the archive, other than `except`, with an unfinished board.
    public func unfinishedDay(except: Int?) -> Int? {
        archiveDays.first { day in day != except && Level.playable.contains { !isDone(day: day, level: $0) } }
    }

    /// The most recent day, other than `except`, where this difficulty isn't done.
    public func unfinishedAt(level: Level, except: Int?) -> Int? {
        archiveDays.first { $0 != except && !isDone(day: $0, level: level) }
    }

    /// The mark on a level tab: "✓" when done, "1/3" once a word is found, else empty.
    public func tabBadge(day: Int, level: Level, wordCount: Int) -> String {
        if isDone(day: day, level: level) { return "✓" }
        let found = record(day: day, level: level).found.count
        return found > 0 ? "\(found)/\(wordCount)" : ""
    }

    public func canGoBack(from day: Int) -> Bool { day > 1 }
    public func canGoForward(from day: Int) -> Bool { day < today }

    public func dayRows() -> [DayRow] {
        archiveDays.map { day in
            let done = Level.playable.filter { isDone(day: day, level: $0) }
            return DayRow(day: day, done: done, buttonLabel: done.count < Level.playable.count ? "Play" : "Open")
        }
    }

    /// Records what a finish won: the world record, else a country record, else a local one.
    /// Returns whether anything changed, so the end card knows to refresh.
    @discardableResult
    public func applyRecordWins(_ wins: RecordWins, day: Int, level: Level) -> Bool {
        guard wins.any else { return false }
        var progress = record(day: day, level: level)
        if wins.world {
            progress.newRecord = true
        } else {
            progress.newRegional = wins.country ? .country : .local
        }
        setRecord(progress, day: day, level: level)
        return true
    }

    /// Writes any unsaved change.
    public func saveNow() {
        guard dirty else { return }
        dirty = false
        var file = StoreFile()
        file.stats = stats
        file.tutorialDone = tutorialDone
        for (day, levels) in days {
            file.days[String(day)] = Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private var archiveDays: StrideThrough<Int> {
        stride(from: today, through: max(1, today - Self.keepDays), by: -1)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(StoreFile.self, from: data)
        else { return }
        stats = file.stats
        tutorialDone = file.tutorialDone
        for (key, levels) in file.days {
            guard let day = Int(key) else { continue }
            for (name, progress) in levels {
                if let level = Level(rawValue: name), Level.playable.contains(level) { days[day, default: [:]][level] = progress }
            }
        }
    }

    private func prune() {
        days = days.filter { $0.key >= today - Self.keepDays }
    }
}

/// The file format, the same shape as the web game's localStorage value. Bad entries are skipped.
private struct StoreFile: Codable {
    var days: [String: [String: LevelProgress]] = [:]
    var stats = Stats()
    var tutorialDone = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case days, stats, tutorialDone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawDays = (try? c.decode([String: Lossy<[String: Lossy<LevelProgress>]>].self, forKey: .days)) ?? [:]
        days = rawDays.compactMapValues { $0.value?.compactMapValues(\.value) }
        stats = (try? c.decode(Stats.self, forKey: .stats)) ?? Stats()
        tutorialDone = (try? c.decode(Bool.self, forKey: .tutorialDone)) ?? false
    }
}

/// Decodes to nil instead of throwing.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
