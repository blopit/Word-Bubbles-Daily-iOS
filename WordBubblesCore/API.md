# WordBubblesCore API

The game's rules, with no UI. The app holds no game rules: it renders the state below, sends touches in, and turns
returned `GameEvent`s into animation, sound, haptics and flashes. Earlier-built types (`Level`, `Bubble`, `Puzzle`,
`GameData`, `Engine`, `BoardLayout`, `RandomSource`, `Mulberry32`) are unchanged.

## How the pieces fit

```swift
let today = Engine.dayNumber(for: Date())
let store = ProgressStore(url: saveURL, today: today)      // one per app
let records = RecordsClient()                              // one per app
let place = Place.detect()                                 // from the device time zone

var day = today
var level = store.initialLevel(day: day)                   // the tutorial on the first visit
var session = GameSession(day: day, level: level, store: store)
var swipe = SwipeTracker()
```

- **Open a board:** `session.leave()` on the old one, then make a new `GameSession`. That is the JS `render()`: it
  resets the combo, restores the full order and starts the clock. Keep `session` in an `@Observable` model; it is a
  struct, so every mutation is seen.
- **After a day/tab change:** `store.level(forDay:stayingOn:)` gives the level to show. `store.today` only moves when
  you call `store.rollover(today:)`, so call it when the day number changes (the website reloads at that point).
- **Board layout:** `BoardLayout.compute(width:height:count: session.order.count)`; the nth point belongs to
  `session.order[n]`. Recompute on `.shuffled`. Consumed bubbles keep their spot until a shuffle.
- **Hit test:** `BoardLayout.hitTest(point:centers:radius:consumed: session.consumed)` with
  `radius: diameter / 2`, then `swipe.pointerDown(hit:session:)`, `pointerMove`, `pointerUp`.
- **Tray tiles:** tapping one calls `session.removeFromChain(id)`. The Clear button (web: Esc) calls `clearChain()`;
  backspace removes `chain.last`.
- **Input blocking:** there is no `busy`. Apply state now, animate from the events, and block input during the
  animation (about 620ms for a lock or bonus, 420ms for a reveal in the web game).
- **Animating the tray:** `chain` is the truth, so diff it. `.unpicked` means "play the put-back sound", not "a tile
  moved": a put-back that completes a word sends `.wordLocked` only. A hint reveal removes its bubbles from `chain`
  with no `.unpicked`.
- **App lifecycle:** `session.pause()` on background, `session.resume()` on return.
- **The finish** (on `.finished`):

  ```swift
  var card = ResultCard.make(day: day, level: level, store: store, place: place, records: await records.snapshot)
  if let board = session.finishedBoard {                    // nil for tutorial and forfeited boards
      let wins = await records.submitFinish(board, place: place)
      if store.applyRecordWins(wins, day: day, level: level) { /* rebuild card, play the earn sound */ }
  }
  ```

  `session.progress` is a copy from before those wins, so read `newRecord`/`newRegional` from the store, or via
  `ResultCard` and `ShareText`, which do.
- **Records while a board is open:** call `records.refresh(day:level:bubbleCount:place:)` on open and every 30s (the
  web game's poll). Never throws; offline, `snapshot` stays nil and the card shows medals only.

### Events and flashes

Handle events in order and show each non-nil `event.flash`; events are ordered so that the last flash is the one the
web game leaves on screen (`.starEarned` comes before `.wordLocked` for that reason). A flash clears after 1.9s.

| Event | Sound in the web game |
| --- | --- |
| `.picked` | `pick(chainLength - 1, combo)`, plus a 6ms vibrate |
| `.unpicked` | `unpick` |
| `.wordLocked` | `lock(combo)`, plus a 10ms vibrate; `win` if `completesBoard` (via `.finished`) |
| `.bonusCollected` | `bonus` |
| `.bonusInline` | `bonus` |
| `.nearMiss` | `near`, shake the tray |
| `.tooManyLetters` | `wrong`, shake the tray |
| `.comboBroken` | `crack` only when `wasCombo` |
| `.starEarned` | `earn`, bump the score |
| `.hintRevealed`, `.wordRevealed` | `hint` |
| `.shuffled` | `shuffle` |
| `.finished` | `win`, confetti |

Bonus tone for the fly-in: `isSecret ? "secret" : "gold"`, separate from the flash tone.

### Small UI rules from the web game

- Score, clock, day navigation and level tabs are hidden in the tutorial.
- Prev day disabled: `!store.canGoBack(from:)`. Next day disabled: `!store.canGoForward(from:)`. Today button hidden
  when `day == store.today`. Day title: `DayFormatter.full(day:)`, with `relative(day:today:)` beneath it.
- `session.bonusButton` is nearly always nil, because `addToChain` collects bonus words itself. It shows only when a
  hint reveal leaves a bonus word in the tray. The tray's letter count is hidden while the button shows.
- `session.comboText` is the badge; `session.heat` (0 to 3) tints the tray.
- `session.clock` is nil in the tutorial. Poll it about every 500ms. `clock.medal == nil` means no medal.
- The `.play` result action needs a new session on that day; `.switchLevel` a new session on the same day.
- "Your days": `store.dayRows()` with `GameText.Days`, stats from `store.stats`, and `GameText.countdown(now:)`.
- Help: `GameText.Help`. Replay tutorial: a new `GameSession(day: store.today, level: .tutorial, ...)`.
- Tab marks: `store.tabBadge(day:level:wordCount:)`.

## Signatures

### Saved games

```swift
public enum RegionalTier: String, Codable, Hashable, Sendable { case country, local }

public struct LevelProgress: Codable, Equatable, Sendable {
    public var found: [Int]
    public var consumed: [String]
    public var moves: Int
    public var hints: [Int: Int]
    public var done: Bool
    public var points: Int
    public var bestCombo: Int
    public var bonus: [String]
    public var elapsed: Double            // milliseconds
    public var usedHint: Bool
    public var newRecord: Bool
    public var newRegional: RegionalTier?
    public init()
    public var forfeitedMedal: Bool { get }
}

public struct Stats: Codable, Equatable, Sendable {
    public var days: Int
    public var streak: Int
    public var best: Int
    public var perfect: Int
    public var lastDay: Int?
    public init(days: Int = 0, streak: Int = 0, best: Int = 0, perfect: Int = 0, lastDay: Int? = nil)
    public mutating func record(day: Int, perfect isPerfect: Bool)
}

public struct DayRow: Equatable, Sendable {
    public let day: Int
    public let done: [Level]
    public let buttonLabel: String        // "Play" or "Open"
}

public final class ProgressStore {        // not thread-safe: use from one actor
    public static let keepDays: Int       // 400
    public private(set) var today: Int
    public private(set) var stats: Stats
    public private(set) var tutorialDone: Bool
    public init(url: URL, today: Int)
    public func rollover(today: Int)
    public func record(day: Int, level: Level) -> LevelProgress
    public func setRecord(_ progress: LevelProgress, day: Int, level: Level, persist: Bool = true)
    public func setStats(_ stats: Stats)
    public func setTutorialDone()
    public func isDone(day: Int, level: Level) -> Bool
    public func firstOpenLevel(day: Int) -> Level
    public func initialLevel(day: Int) -> Level
    public func level(forDay day: Int, stayingOn current: Level) -> Level
    public func unfinishedDay(except: Int?) -> Int?
    public func unfinishedAt(level: Level, except: Int?) -> Int?
    public func tabBadge(day: Int, level: Level, wordCount: Int) -> String
    public func canGoBack(from day: Int) -> Bool
    public func canGoForward(from day: Int) -> Bool
    public func dayRows() -> [DayRow]
    @discardableResult
    public func applyRecordWins(_ wins: RecordWins, day: Int, level: Level) -> Bool
    public func saveNow()
}
```

### Playing a board

```swift
public struct SystemRandomSource: RandomSource { public init(); public mutating func next() -> Double }

public enum WordSlot: Equatable, Sendable {
    case solved(String)
    case hinted(String)                   // "TO·AS·…"
    case hidden(letters: Int)
}

public struct BonusButton: Equatable, Sendable {
    public let word: String
    public let isSecret: Bool
    public let label: String              // "✦ Bonus" or "◆ Secret"
}

public struct BonusChip: Equatable, Sendable {
    public let word: String
    public let isSecret: Bool
}

public struct GameSession {
    public let day: Int
    public let level: Level
    public let puzzle: Puzzle
    public private(set) var progress: LevelProgress
    public private(set) var chain: [String]
    public private(set) var order: [String]
    public private(set) var combo: Int
    public private(set) var clean: Bool

    public init(day: Int, level: Level, store: ProgressStore, data: GameData = .shared,
                now: @escaping () -> Date = Date.init)

    // Reading
    public var isTutorial: Bool { get }
    public func bubble(id: String) -> Bubble?
    public var liveBubbles: [Bubble] { get }
    public var consumed: Set<String> { get }
    public var rank: Rank { get }
    public var spelled: String { get }
    public var letterCount: Int { get }
    public var letterCountText: String { get }   // "1 letter", "7 letters"
    public var prompt: String { get }            // the empty tray's text
    public var comboText: String? { get }        // "×3", from 2 up, not capped
    public var heat: Int { get }
    public var scoreAccessibilityLabel: String { get }
    public var liveElapsed: Double { get }       // ms
    public var clock: ClockState? { get }
    public var slots: [WordSlot] { get }
    public var hintTargets: [String: Int] { get } // bubble id -> piece number from 1
    public var bonusButton: BonusButton? { get }
    public var bonusBar: [BonusChip]? { get }    // newest first; nil while hidden
    public var bonusStillPossible: Int { get }
    public var finishedBoard: FinishedBoard? { get }

    // Mutators (all @discardableResult). No events means the input was rejected.
    public mutating func addToChain(_ id: String) -> [GameEvent]
    public mutating func removeFromChain(_ id: String) -> [GameEvent]
    public mutating func clearChain() -> [GameEvent]
    public mutating func collectBonus(_ word: String) -> [GameEvent]
    public mutating func hint() -> [GameEvent]
    public mutating func shuffle<R: RandomSource>(rng: inout R) -> [GameEvent]
    public mutating func shuffle() -> [GameEvent]

    // Lifecycle
    public mutating func replay()
    public mutating func pause()
    public mutating func resume()
    public mutating func leave()
    public func saveNow()
}

public struct SwipeTracker {
    public init()
    public var isActive: Bool { get }
    @discardableResult
    public mutating func pointerDown(hit id: String?, session: inout GameSession) -> [GameEvent]
    @discardableResult
    public mutating func pointerMove(hit id: String?, session: inout GameSession) -> [GameEvent]
    public mutating func pointerUp(session: GameSession)
}

public enum FlashTone: String, Equatable, Sendable { case good, hint, bad, secret }

public struct Flash: Equatable, Sendable {
    public let text: String
    public let tone: FlashTone
    public init(text: String, tone: FlashTone)
}

public enum GameEvent: Equatable, Sendable {
    case picked(id: String, chainLength: Int, combo: Int)
    case unpicked(ids: [String])
    case wordLocked(wordIndex: Int, word: String, ids: [String], gained: Int, combo: Int,
                    isTutorial: Bool, completesBoard: Bool)
    case bonusCollected(word: String, isSecret: Bool, points: Int, ids: [String])
    case bonusAlreadyFound(word: String)
    case nearMiss(isTutorial: Bool)
    case tooManyLetters
    case comboBroken(wasCombo: Bool)
    case starEarned(stars: Int)
    case hintRevealed(wordIndex: Int, chunks: [String], firstHint: Bool)
    case wordRevealed(wordIndex: Int, word: String, ids: [String], points: Int, firstHint: Bool)
    case shuffled
    case finished
    public var flash: Flash? { get }
}
```

`gained` is 0 in the tutorial. `combo` in `.wordLocked` is uncapped; `gained` already applies the ×4 cap.

### Scoring

```swift
public struct Rank: Equatable, Sendable {
    public let stars: Int
    public let fraction: Double
    public let toNext: Double
}

public struct Medal: Equatable, Sendable {
    public let key: String                // gold, silver, bronze, record, country, local
    public let name: String
    public let ms: Int
    public let emoji: String
    public let icon: String?              // records only
}

public struct ClockState: Equatable, Sendable {
    public let medal: Medal?
    public let fractionLeft: Double
    public let timeText: String
    public let accessibilityLabel: String
}

public enum Scoring {
    public static let starAt: [Double]
    public static func multiplier(_ combo: Int) -> Int
    public static func maxPoints(_ puzzle: Puzzle) -> Int
    public static func rank(points: Int, puzzle: Puzzle, finished: Bool = false) -> Rank
    public static func starText(_ stars: Int) -> String
    public static func heat(_ combo: Int) -> Int
    public static func medalTimes(bubbleCount n: Int) -> [Medal]
    public static func medalLadder(day: Int, level: Level, bubbleCount: Int,
                                   records: [String: RecordEntry], place: Place) -> [Medal]
    public static func medalFor(ms: Double, day: Int, level: Level, bubbleCount: Int, progress: LevelProgress,
                                records: [String: RecordEntry], place: Place) -> Medal?
    public static func clock(elapsedMs ms: Double, forfeited: Bool, bubbleCount: Int) -> ClockState
}
```

### End of board

```swift
public enum ResultIcon: String, Equatable, Sendable { case next, earlier, share, play }

public enum ResultAction: Equatable, Sendable {
    case play(day: Int, level: Level)
    case switchLevel(Level)
    case share
}

public struct ResultButton: Equatable, Sendable {
    public let label: String
    public let icon: ResultIcon
    public let action: ResultAction
}

public struct ResultBest: Equatable, Sendable {
    public let key: String?               // Medal key; nil is no medal
    public let icon: String?              // a held record's icon; a medal shows a colored dot
    public let text: String               // "Gold · 0:20", "No medal · 1:40", "Time not recorded"
}

public struct ResultPill: Equatable, Sendable {
    public let key: String
    public let label: String
    public let icon: String?
    public let text: String               // time, or "—"
    public let isEmpty: Bool
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
    public let tag: String                // "Sep 1, 2026 · Easy"
    public let stars: Int
    public let best: ResultBest
    public let pills: [ResultPill]
    public let pointsLine: String         // "330 points · best combo ×3"
    public let words: [String]            // "TO·AS·T"
    public let bonusWords: [BonusChip]    // in found order
    public let tips: [[TextSegment]]      // one inner list per paragraph
    public let summary: [SummaryRow]      // empty until all three are done
    public let showsCountdown: Bool
    public let primary: ResultButton?
    public let secondary: [ResultButton]  // Share is always last
}

public enum ResultCard: Equatable, Sendable {
    case tutorial(TutorialResult)
    case board(BoardResult)
    public static func make(day: Int, level: Level, store: ProgressStore, place: Place,
                            records: [String: RecordEntry]?, data: GameData = .shared,
                            formatter: DayFormatter = DayFormatter()) -> ResultCard
}

public enum ShareText {
    public static func make(day: Int, store: ProgressStore, place: Place, records: [String: RecordEntry],
                            data: GameData = .shared, formatter: DayFormatter = DayFormatter()) -> String
}
```

The share button's "Copied to clipboard" toast is the app's own. The text's records argument is non-optional: pass
`await records.records`, which is empty offline.

### Text

```swift
public enum TextSegment: Equatable, Sendable {
    case plain(String)
    case bold(String)
    case secret(String)                   // the secret color
}

public struct DayFormatter {
    public init(locale: Locale = .current, timeZone: TimeZone = .current)
    public func short(day: Int) -> String                    // "Nov 2"
    public func full(day: Int) -> String                     // "Nov 2, 2026"
    public func weekday(day: Int) -> String                  // "Mon"
    public func relative(day: Int, today: Int) -> String     // "Today", "Yesterday", "Sat"
    public func dayWord(day: Int, today: Int) -> String      // "Today", "Nov 2"
}

public enum GameText {
    public static func time(ms: Double) -> String                                 // "2:05"
    public static func untilMidnight(now: Date, calendar: Calendar = .current) -> String // "9h 05m", "30m"
    public static func countdown(now: Date, calendar: Calendar = .current) -> String     // "New boards in 30m"
    public static func letterCount(_ letters: Int) -> String
    public static func prompt(level: Level) -> String

    public enum Help {
        public static let title: String
        public static let demoChunks: [String]
        public static let demoWord: String
        public static let replayTutorial: String
    }
    public enum Days {
        public static let title: String
        public static let statLabels: [String]   // Days, Streak, Best, 3★ days
        public static let footnote: String
    }
    public enum TutorialResult {
        public static let title: String
        public static let body: String
        public static let button: String
    }
}
```

### Place and records

```swift
public struct PlaceContinent: Equatable, Sendable { public let code: String; public let name: String }
public struct PlaceCountry: Equatable, Sendable { public let code: String; public let name: String; public let flag: String }
public struct PlaceLocal: Equatable, Sendable { public let code: String; public let name: String }

public struct Place: Equatable, Sendable {
    public let continent: PlaceContinent?
    public let country: PlaceCountry?
    public let local: PlaceLocal?
    public init(continent: PlaceContinent? = nil, country: PlaceCountry? = nil, local: PlaceLocal? = nil)
    public static let nowhere: Place
    public static func detect(timeZoneID zone: String = TimeZone.current.identifier) -> Place
    public func recordKeys(day: Int, level: Level) -> [RecordKey]
}

public enum RecordTier: String, Hashable, Sendable { case world, country, local }

public struct RecordKey: Equatable, Hashable, Sendable {
    public let tier: RecordTier
    public let id: String                 // d<day>-<level>[-c-<CC>|-z-<code>]
}

public struct RecordEntry: Equatable, Hashable, Sendable {
    public let ms: Int
    public let pts: Int
    public init(ms: Int, pts: Int)
}

public enum Records {
    public static func beats(_ a: RecordEntry, _ b: RecordEntry?) -> Bool
    public static func holds(_ a: RecordEntry, _ b: RecordEntry?) -> Bool
    public static func plausible(ms: Double, bubbleCount: Int) -> Bool
}

public struct FinishedBoard: Equatable, Sendable {
    public let day: Int
    public let level: Level
    public let progress: LevelProgress
    public let bubbleCount: Int
    public init(day: Int, level: Level, progress: LevelProgress, bubbleCount: Int)
}

public struct RecordWins: Equatable, Sendable {
    public var world: Bool
    public var country: Bool
    public var local: Bool
    public init(world: Bool = false, country: Bool = false, local: Bool = false)
    public var any: Bool { get }
}

public enum RecordFetch: Equatable, Sendable {
    case found(RecordEntry?)
    case failed
}

public protocol RecordsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public struct URLSessionRecordsTransport: RecordsTransport {
    public init(session: URLSession = .shared)
    public func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public actor RecordsClient {
    public static let defaultURL: URL
    public private(set) var records: [String: RecordEntry]
    public private(set) var isAvailable: Bool
    public var snapshot: [String: RecordEntry]? { get }     // nil until the server has answered
    public init(transport: any RecordsTransport = URLSessionRecordsTransport(),
                baseURL: URL = RecordsClient.defaultURL)
    public func fetch(id: String) async -> RecordFetch
    @discardableResult
    public func refresh(day: Int, level: Level, bubbleCount: Int, place: Place) async -> [String: RecordEntry]
    public func submitFinish(_ board: FinishedBoard, place: Place) async -> RecordWins
}
```
