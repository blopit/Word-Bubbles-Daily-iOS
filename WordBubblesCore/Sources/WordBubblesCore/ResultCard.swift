import Foundation

public enum ResultIcon: String, Equatable, Sendable {
    case next, earlier, share, play
}

public enum ResultAction: Equatable, Sendable {
    /// Go to another day's board.
    case play(day: Int, level: Level)
    /// Another board on the same day.
    case switchLevel(Level)
    case share
}

public struct ResultButton: Equatable, Sendable {
    public let label: String
    public let icon: ResultIcon
    public let action: ResultAction
}

/// The line about the best thing this time earned.
public struct ResultBest: Equatable, Sendable {
    /// A `Medal` key, or nil for no medal.
    public let key: String?
    /// Set for a held record; a medal shows a colored dot instead.
    public let icon: String?
    public let text: String
}

/// One step of the row of records then medals.
public struct ResultPill: Equatable, Sendable {
    public let key: String
    /// "World", the country or the local area for records; the medal name for medals.
    public let label: String
    public let icon: String?
    /// The time, or "—" for a record no one has set.
    public let text: String
    public let isEmpty: Bool
    /// This is your best. At most one pill is.
    public let isHit: Bool
    public let accessibilityLabel: String
}

public struct SummaryRow: Equatable, Sendable {
    public let label: String
    public let value: String
}

public struct TutorialResult: Equatable, Sendable {
    public let title: String
    public let body: String
    public let primary: ResultButton
}

public struct BoardResult: Equatable, Sendable {
    public let tag: String
    public let stars: Int
    public let best: ResultBest
    public let pills: [ResultPill]
    public let pointsLine: String
    /// Each word cut into its pieces: "TO·AS·T".
    public let words: [String]
    public let bonusWords: [BonusChip]
    /// Each inner list is one paragraph.
    public let tips: [[TextSegment]]
    /// Empty until all three boards of the day are done.
    public let summary: [SummaryRow]
    /// Show `GameText.countdown` under the summary.
    public let showsCountdown: Bool
    public let primary: ResultButton?
    /// The small buttons. Share is always last.
    public let secondary: [ResultButton]
}

/// The end-of-board card.
public enum ResultCard: Equatable, Sendable {
    case tutorial(TutorialResult)
    case board(BoardResult)

    /// `records` is `RecordsClient.snapshot`: nil with no server, which hides the record pills.
    /// Builds from the store, so call it again after `applyRecordWins`.
    public static func make(
        day: Int, level: Level, store: ProgressStore, place: Place, records: [String: RecordEntry]?,
        data: GameData = .shared, formatter: DayFormatter = DayFormatter()
    ) -> ResultCard {
        guard level != .tutorial else {
            let button = ResultButton(
                label: GameText.TutorialResult.button, icon: .play, action: .play(day: store.today, level: .easy)
            )
            return .tutorial(TutorialResult(
                title: GameText.TutorialResult.title, body: GameText.TutorialResult.body, primary: button
            ))
        }
        let puzzle = data.puzzle(day: day, level: level)
        let progress = store.record(day: day, level: level)
        let isSecret = { (word: String) in data.isSecret(word: word, theme: puzzle.theme) }
        let (best, pills) = medals(day: day, puzzle: puzzle, progress: progress, place: place, records: records)
        let (summaryRows, countdown) = summary(day: day, store: store, data: data)
        let (primary, secondary) = actions(day: day, level: level, store: store, formatter: formatter)
        return .board(BoardResult(
            tag: formatter.full(day: day) + " · " + level.label,
            stars: Scoring.rank(points: progress.points, puzzle: puzzle, finished: true).stars,
            best: best, pills: pills,
            pointsLine: "\(progress.points) points"
                + (progress.bestCombo >= 2 ? " · best combo ×\(Scoring.multiplier(progress.bestCombo))" : ""),
            words: puzzle.chunksByWord.map { $0.joined(separator: "·") },
            bonusWords: progress.bonus.map { BonusChip(word: $0, isSecret: isSecret($0)) },
            tips: tips(
                allBonus: data.bonusEntries(day: day, level: level), have: Set(progress.bonus), isSecret: isSecret
            ),
            summary: summaryRows, showsCountdown: countdown, primary: primary, secondary: secondary
        ))
    }

    private struct RecordSlot {
        let key: String
        let label: String
        let name: String
        let entry: RecordEntry?
        let icon: String
    }

    /// Always the same slots: world, then the player's country and local area, filled or not.
    private static func recordSlots(day: Int, level: Level, place: Place, records: [String: RecordEntry]?) -> [RecordSlot] {
        guard let records else { return [] }
        return place.recordKeys(day: day, level: level).map { key in
            let entry = records[key.id]
            switch key.tier {
            case .world:
                return RecordSlot(key: "record", label: "World", name: "World record", entry: entry, icon: "👑")
            case .country:
                let name = place.country?.name ?? ""
                return RecordSlot(key: "country", label: name, name: name + " record", entry: entry, icon: place.country?.flag ?? "")
            case .local:
                let name = place.local?.name ?? ""
                return RecordSlot(key: "local", label: name, name: name + " record", entry: entry, icon: "📍")
            }
        }
    }

    private static func medals(
        day: Int, puzzle: Puzzle, progress: LevelProgress, place: Place, records: [String: RecordEntry]?
    ) -> (ResultBest, [ResultPill]) {
        let elapsed = progress.elapsed
        let mine = RecordEntry(ms: Int(JSMath.round(elapsed)), pts: progress.points)
        let slots = recordSlots(day: day, level: puzzle.level, place: place, records: records)
        let times = Scoring.medalTimes(bubbleCount: puzzle.bubbles.count)
        let hinted = progress.forfeitedMedal
        // The best thing this time earned: a record you hold (world > country > local), else a medal.
        let held = hinted || mine.ms == 0 ? nil : slots.first { Records.holds(mine, $0.entry) }
        let medal = hinted || mine.ms == 0 ? nil : times.first { mine.ms <= $0.ms }
        let bestKey = held?.key ?? medal?.key

        let time = GameText.time(ms: elapsed)
        let text = elapsed == 0 ? "Time not recorded" : ((held?.name ?? medal?.name).map { $0 + " · " } ?? "No medal · ") + time
        let best = ResultBest(key: bestKey, icon: held?.icon, text: text)

        // A narrower record that is the same as a broader one isn't repeated.
        var shown: [RecordSlot] = []
        for slot in slots where !shown.contains(where: { $0.entry == slot.entry }) { shown.append(slot) }

        let recordPills = shown.map { slot -> ResultPill in
            let hit = slot.key == bestKey
            let timeText = slot.entry.map { GameText.time(ms: Double($0.ms)) }
            return ResultPill(
                key: slot.key, label: slot.label, icon: slot.icon, text: timeText ?? "—", isEmpty: slot.entry == nil, isHit: hit,
                accessibilityLabel: slot.name + (timeText.map { " " + $0 } ?? ", none yet") + (hit ? ", yours" : "")
            )
        }
        let medalPills = times.map { medal -> ResultPill in
            let hit = medal.key == bestKey
            let timeText = GameText.time(ms: Double(medal.ms))
            return ResultPill(
                key: medal.key, label: medal.name, icon: nil, text: timeText, isEmpty: false, isHit: hit,
                accessibilityLabel: medal.name + " " + timeText + (hit ? ", yours" : "")
            )
        }
        return (best, recordPills + medalPills)
    }

    /// Longest missed bonus word, then the secret-word sentence.
    static func tips(
        allBonus: [(key: String, word: String)], have: Set<String>, isSecret: (String) -> Bool
    ) -> [[TextSegment]] {
        guard !allBonus.isEmpty else { return [] }
        let byLength = Set(allBonus.map(\.word)).sorted { ($1.count, $0) < ($0.count, $1) }
        var paragraphs: [[TextSegment]] = []
        if let missed = byLength.first(where: { !have.contains($0) }) {
            let top = byLength[0]
            let lead = have.contains(top) ? "You found the longest bonus word, \(top)! " : ""
            paragraphs.append([.plain(lead + "Longest bonus word you missed: "), .bold(missed)])
        } else {
            paragraphs.append([.plain("You found every bonus word!")])
        }
        let secrets = byLength.filter(isSecret)
        guard !secrets.isEmpty else { return paragraphs }
        let found = secrets.filter { have.contains($0) }
        let missed = secrets.filter { !have.contains($0) }
        var line: [TextSegment] = []
        if missed.isEmpty {
            line.append(.plain(found.count == 1 ? "You found the secret word, " : "You found every secret word: "))
            line += secretList(found)
            line.append(.plain("!"))
        } else {
            if !found.isEmpty {
                line.append(.plain(found.count == 1 ? "You found the secret word, " : "You found the secret words "))
                line += secretList(found)
                line.append(.plain("! "))
            }
            line.append(.plain(missed.count == 1 ? "Secret word you missed: " : "Secret words you missed: "))
            line += secretList(missed)
        }
        paragraphs.append(line)
        return paragraphs
    }

    private static func secretList(_ words: [String]) -> [TextSegment] {
        var segments: [TextSegment] = []
        for (index, word) in words.enumerated() {
            if index > 0 { segments.append(.plain(index == words.count - 1 ? " and " : ", ")) }
            segments.append(.secret(word))
        }
        return segments
    }

    private static func summary(day: Int, store: ProgressStore, data: GameData) -> ([SummaryRow], Bool) {
        guard Level.playable.allSatisfy({ store.isDone(day: day, level: $0) }) else { return ([], false) }
        var rows = Level.playable.map { level -> SummaryRow in
            let points = store.record(day: day, level: level).points
            let stars = Scoring.rank(points: points, puzzle: data.puzzle(day: day, level: level), finished: true).stars
            return SummaryRow(label: level.label, value: Scoring.starText(stars) + " · \(points)")
        }
        guard day == store.today else { return (rows, false) }
        let streak = store.stats.streak
        rows.append(SummaryRow(label: "Streak", value: "\(streak) \(streak == 1 ? "day" : "days")"))
        return (rows, true)
    }

    /// The big button stays on this difficulty; the other open board on this day is the smaller choice.
    private static func actions(
        day: Int, level: Level, store: ProgressStore, formatter: DayFormatter
    ) -> (ResultButton?, [ResultButton]) {
        let next = Level.playable.first { !store.isDone(day: day, level: $0) }
        let same = store.unfinishedAt(level: level, except: day)
        let other = store.unfinishedDay(except: day)
        let otherLevel = other.map { store.firstOpenLevel(day: $0) }
        let label = { (day: Int, level: Level) in formatter.dayWord(day: day, today: store.today) + " " + level.label }

        var primary: ResultButton?
        if let same {
            primary = ResultButton(label: "Play " + label(same, level), icon: .next, action: .play(day: same, level: level))
        } else if let next {
            primary = ResultButton(label: "Play " + next.label, icon: .next, action: .switchLevel(next))
        } else if let other, let otherLevel {
            primary = ResultButton(label: "Play " + label(other, otherLevel), icon: .earlier, action: .play(day: other, level: otherLevel))
        }

        var row: [ResultButton] = []
        if same != nil, let next {
            row.append(ResultButton(label: next.label, icon: .next, action: .switchLevel(next)))
        }
        if let other, let otherLevel, other != same, same != nil || next != nil {
            row.append(ResultButton(label: label(other, otherLevel), icon: .earlier, action: .play(day: other, level: otherLevel)))
        }
        row.append(ResultButton(label: "Share", icon: .share, action: .share))
        return (primary, row)
    }
}

/// The spoiler-free summary players paste to friends.
public enum ShareText {
    public static func make(
        day: Int, store: ProgressStore, place: Place, records: [String: RecordEntry],
        data: GameData = .shared, formatter: DayFormatter = DayFormatter()
    ) -> String {
        var lines = ["Word Bubbles · " + formatter.full(day: day)]
        for level in Level.playable {
            let progress = store.record(day: day, level: level)
            guard progress.done else {
                lines.append("\(level.icon) \(level.label) —")
                continue
            }
            let puzzle = data.puzzle(day: day, level: level)
            let stars = Scoring.rank(points: progress.points, puzzle: puzzle, finished: true).stars
            let secrets = progress.bonus.filter { data.isSecret(word: $0, theme: puzzle.theme) }.count
            var line = "\(level.icon) \(level.label) \(Scoring.starText(stars))"
            line += badge(day: day, puzzle: puzzle, progress: progress, place: place, records: records)
            line += " \(progress.points)"
            if progress.elapsed != 0 { line += " " + GameText.time(ms: progress.elapsed) }
            if progress.bestCombo >= 2 { line += " · ×\(Scoring.multiplier(progress.bestCombo)) combo" }
            if !progress.bonus.isEmpty { line += " · ✦\(progress.bonus.count)" }
            if secrets > 0 { line += " · ◆\(secrets)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func badge(
        day: Int, puzzle: Puzzle, progress: LevelProgress, place: Place, records: [String: RecordEntry]
    ) -> String {
        if progress.forfeitedMedal { return " no medal" }
        if progress.newRecord { return " 👑" }
        if progress.newRegional == .country, let country = place.country { return " " + country.flag }
        if progress.newRegional == .local { return " 📍" }
        let medal = Scoring.medalFor(
            ms: progress.elapsed, day: day, level: puzzle.level, bubbleCount: puzzle.bubbles.count,
            progress: progress, records: records, place: place
        )
        return medal.map { " " + $0.emoji } ?? ""
    }
}
