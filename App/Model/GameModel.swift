import CoreGraphics
import Foundation
import Observation
import WordBubblesCore

/// What the model is built from, so tests can swap the clock, the scheduler and the speakers.
@MainActor
struct GameDependencies {
    var store: ProgressStore
    var records: RecordsClient
    var place: Place
    var sound: SoundPlaying
    var haptics: HapticPlaying
    var scheduler: Scheduling
    var now: () -> Date = Date.init
    var measure: (String) -> Double
    var reduceMotion: () -> Bool
    var usesNetwork = true
    var calendar: Calendar = .current
}

/// The screen's state. The session is the truth and is deliberately not observed: the properties below are what the
/// views read, and they change only when something on screen should, so a swipe touches a tile, a bubble and a flight
/// rather than the whole view tree. No game rules live here: touches go in, `GameEvent`s come out and get played.
@MainActor
@Observable
final class GameModel {
    static let flightSeconds = 0.32
    static let flashSeconds = 1.9
    static let clockSeconds = 0.5
    static let dayCheckSeconds = 60.0
    static let recordsSeconds = 30.0

    // MARK: Dependencies

    @ObservationIgnored let store: ProgressStore
    @ObservationIgnored let records: RecordsClient
    @ObservationIgnored let place: Place
    @ObservationIgnored let sound: SoundPlaying
    @ObservationIgnored let haptics: HapticPlaying
    @ObservationIgnored let scheduler: Scheduling
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let measure: (String) -> Double
    @ObservationIgnored let reduceMotion: () -> Bool
    @ObservationIgnored let usesNetwork: Bool
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let formatter = DayFormatter()

    // MARK: Game state, not observed

    @ObservationIgnored private(set) var session: GameSession
    @ObservationIgnored var swipe = SwipeTracker()
    @ObservationIgnored var lastHit: String?
    @ObservationIgnored var touching = false
    @ObservationIgnored var centers: [(id: String, center: CGPoint)] = []
    @ObservationIgnored var radius = 0.0
    @ObservationIgnored var bubbleStates: [String: BubbleState] = [:]
    @ObservationIgnored var timeline: [ScheduledWork] = []
    @ObservationIgnored var flightFinishers: [Int: () -> Void] = [:]
    @ObservationIgnored var nextFlightID = 0
    @ObservationIgnored var flashWork: ScheduledWork?
    @ObservationIgnored var clockWork: ScheduledWork?
    @ObservationIgnored var dayWork: ScheduledWork?
    @ObservationIgnored var recordsWork: ScheduledWork?
    @ObservationIgnored var starsWork: [ScheduledWork] = []
    @ObservationIgnored var cachedRecords: [String: RecordEntry]?
    @ObservationIgnored var allRecords: [String: RecordEntry] = [:]
    @ObservationIgnored var shownResultKey: String?
    @ObservationIgnored var isForeground = true
    @ObservationIgnored var trayRoomForCount = true

    // Measured in the game's coordinate space. Reading these never redraws anything.
    @ObservationIgnored var boardFrame: CGRect = .zero
    @ObservationIgnored var trayFrame: CGRect = .zero
    @ObservationIgnored var slotFrames: [Int: CGRect] = [:]
    @ObservationIgnored var chipFrames: [String: CGRect] = [:]

    // MARK: Observed display state

    var day: Int
    var level: Level
    var theme = ""
    var dayName = ""
    var dayLabel = ""
    var canGoBack = false
    var canGoForward = false
    var showsToday = false
    var tabs: [TabDisplay] = []

    var slots: [SlotDisplay] = []
    var bonusChips: [BonusChip]?
    var arrivingChip: String?

    var tiles: [TrayTile] = []
    var trayActive = false
    var trayScale = 1.0
    var lockTone: LockTone?
    var trayFrozen = false
    var showsLetterCount = false
    var letterCountText = ""
    var prompt = ""
    var comboText: String?
    var comboBump = 0
    var heat = 0
    var shakeCount = 0
    var bonusButton: BonusButton?
    var flash: Flash?
    var flashCount = 0

    var points = 0
    var stars = 0
    var scoreBump = 0
    var scoreLabel = ""
    var clock: ClockState?

    var bubbles: [Bubble] = []
    var boardGeneration = 0
    var diameter = 0.0
    var fontSize = 0.0
    var orderCount = 0

    var flights: [Flight] = []
    var celebration: [CelebrationBubble] = []

    var result: ResultCard?
    var resultAnimates = false
    var overlay: Overlay?
    var dayRows: [DayRow] = []
    var inputBlocked = false
    var slideCount = 0
    var slideDirection = SlideDirection.left
    var soundOn: Bool

    var isTutorial: Bool { level == .tutorial }
    var flightDuration: Double { reduceMotion() ? 0 : Self.flightSeconds }

    init(_ dependencies: GameDependencies) {
        store = dependencies.store
        records = dependencies.records
        place = dependencies.place
        sound = dependencies.sound
        haptics = dependencies.haptics
        scheduler = dependencies.scheduler
        now = dependencies.now
        measure = dependencies.measure
        reduceMotion = dependencies.reduceMotion
        usesNetwork = dependencies.usesNetwork
        calendar = dependencies.calendar
        soundOn = dependencies.sound.isOn

        let today = dependencies.store.today
        let first = dependencies.store.initialLevel(day: today)
        day = today
        level = first
        session = GameSession(day: today, level: first, store: dependencies.store, now: dependencies.now)
        loadBoard()
        scheduleDayCheck()
    }

    // MARK: Opening boards

    /// Leaves the current board and opens another, with the day-change slide if `slide` is set.
    func open(day newDay: Int, level newLevel: Level, slide: SlideDirection? = nil) {
        session.leave()
        session = GameSession(day: newDay, level: newLevel, store: store, now: now)
        day = newDay
        level = newLevel
        loadBoard()
        if let slide {
            slideDirection = slide
            slideCount += 1
        }
    }

    /// The JS `render()`: rebuilds every display property from the new session.
    private func loadBoard() {
        cancelTimeline()
        starsWork.forEach { $0.cancel() }
        starsWork = []
        swipe = SwipeTracker()
        lastHit = nil
        inputBlocked = false
        finishAllFlights()
        flights = []
        celebration = []
        tiles = []
        lockTone = nil
        trayFrozen = false
        arrivingChip = nil
        slotFrames = [:]
        chipFrames = [:]
        clearFlash()

        theme = session.puzzle.theme
        prompt = session.prompt
        bubbles = session.puzzle.bubbles
        let consumed = session.consumed
        bubbleStates = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.id, BubbleState(consumed: consumed.contains($0.id))) })
        boardGeneration += 1

        cachedRecords = nil
        allRecords = [:]
        syncHeader()
        syncScore()
        syncSlots()
        syncTrayText()
        layoutBoard()
        if session.progress.done { showResultCard() } else { result = nil }
        startClock()
        startRecordsForBoard()
    }

    func syncHeader() {
        dayName = formatter.relative(day: day, today: store.today)
        dayLabel = formatter.full(day: day)
        canGoBack = store.canGoBack(from: day)
        canGoForward = store.canGoForward(from: day)
        showsToday = day != store.today
        syncTabs()
    }

    func syncTabs() {
        tabs = Level.playable.map { tab in
            let words = GameData.shared.puzzle(day: day, level: tab).words.count
            return TabDisplay(level: tab, badge: store.tabBadge(day: day, level: tab, wordCount: words))
        }
    }

    // MARK: Syncing display from the session

    /// Writes only real changes, so a view that reads a value redraws only when the value moves.
    private func set<Value: Equatable>(_ path: ReferenceWritableKeyPath<GameModel, Value>, _ value: Value) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }

    /// Combo, score, stars and the bonus bar.
    func syncScore() {
        let session = self.session
        set(\.comboText, session.comboText)
        set(\.heat, session.heat)
        set(\.points, session.progress.points)
        set(\.stars, session.rank.stars)
        set(\.scoreLabel, session.scoreAccessibilityLabel)
        set(\.bonusChips, session.bonusBar)
    }

    func syncSlots() {
        set(\.slots, session.slots.enumerated().map { index, slot in
            SlotDisplay(id: index, slot: slot, arriving: slots.first { $0.id == index }?.arriving ?? false)
        })
        let targets = session.hintTargets
        for (id, state) in bubbleStates {
            let number = targets[id]
            if state.hintNumber != number { state.hintNumber = number }
        }
    }

    func syncTrayText() {
        let letters = tiles.reduce(0) { $0 + $1.text.count }
        set(\.trayActive, !tiles.isEmpty)
        set(\.letterCountText, GameText.letterCount(letters))
        set(\.bonusButton, trayFrozen ? nil : session.bonusButton)
        set(\.showsLetterCount, !tiles.isEmpty && !trayFrozen && bonusButton == nil && trayRoomForCount)
    }

    // MARK: Board geometry

    /// Called with the board's real frame. Only a change of size lays the bubbles out again.
    func boardMeasured(_ frame: CGRect) {
        let resized = frame.size != boardFrame.size
        boardFrame = frame
        if resized { layoutBoard() }
    }

    func layoutBoard() {
        let order = session.order
        orderCount = order.count
        let layout = BoardLayout.compute(width: boardFrame.width, height: boardFrame.height, count: order.count)
        radius = layout.diameter / 2
        if diameter != layout.diameter { diameter = layout.diameter }
        if fontSize != layout.fontSize { fontSize = layout.fontSize }
        centers = zip(order, layout.points).map { (id: $0, center: $1) }
        for (id, point) in centers {
            guard let state = bubbleStates[id], state.point != point else { continue }
            state.point = point
        }
    }

    func trayMeasured(_ frame: CGRect) {
        let resized = frame.size != trayFrame.size
        trayFrame = frame
        if resized { layoutTiles() }
    }

    func layoutTiles() {
        let result = TrayLayout.frames(
            texts: tiles.map(\.text), pillWidth: trayFrame.width, pillHeight: trayFrame.height,
            locked: lockTone != nil, measure: measure
        )
        var updated = tiles
        for index in updated.indices where index < result.rects.count {
            updated[index].frame = result.rects[index]
        }
        if updated != tiles { tiles = updated }
        if trayScale != result.scale { trayScale = result.scale }
        trayRoomForCount = result.roomForCount
    }

    func bubbleRect(_ id: String) -> CGRect? {
        guard let center = centers.first(where: { $0.id == id })?.center ?? bubbleStates[id]?.point, diameter > 0 else { return nil }
        return CGRect(
            x: boardFrame.minX + center.x - diameter / 2, y: boardFrame.minY + center.y - diameter / 2,
            width: diameter, height: diameter
        )
    }

    func tileRect(_ tile: TrayTile) -> CGRect {
        tile.frame.offsetBy(dx: trayFrame.minX, dy: trayFrame.minY)
    }

    // MARK: Touches

    /// Every drag sample, in board coordinates. The first of a touch is a press; a later one that returns to exactly
    /// the same spot is still a move, or sliding back to the first bubble would read as a tap on it.
    func touch(at point: CGPoint) {
        if touching {
            touchMoved(to: point)
        } else {
            touching = true
            touchBegan(at: point)
        }
    }

    /// A finger came down on the board.
    func touchBegan(at point: CGPoint) {
        lastHit = nil
        guard !inputBlocked, result == nil else { return }
        let hit = hitTest(point)
        lastHit = hit
        guard hit != nil else { return }
        apply(swipe.pointerDown(hit: hit, session: &session))
    }

    /// The finger moved. Does nothing until it crosses into a different bubble, so drag samples stay cheap.
    func touchMoved(to point: CGPoint) {
        guard swipe.isActive, !inputBlocked, let hit = hitTest(point), hit != lastHit else { return }
        lastHit = hit
        apply(swipe.pointerMove(hit: hit, session: &session))
    }

    func touchEnded() {
        touching = false
        lastHit = nil
        swipe.pointerUp(session: session)
    }

    private func hitTest(_ point: CGPoint) -> String? {
        BoardLayout.hitTest(point: point, centers: centers, radius: radius, consumed: session.consumed)
    }

    /// A bubble activated without a touch path, as VoiceOver does.
    func activateBubble(_ id: String) {
        guard !inputBlocked, result == nil else { return }
        apply(swipe.pointerDown(hit: id, session: &session))
        swipe.pointerUp(session: session)
    }

    func tapTile(_ id: String) {
        guard !inputBlocked else { return }
        apply(session.removeFromChain(id))
    }

    func clearTray() {
        guard !inputBlocked else { return }
        apply(session.clearChain())
    }

    func collectBonusButton() {
        guard !inputBlocked, let word = session.bonusButton?.word else { return }
        apply(session.collectBonus(word))
    }

    func useHint() {
        guard !inputBlocked else { return }
        apply(session.hint())
    }

    func shuffle() {
        guard !inputBlocked else { return }
        apply(session.shuffle())
    }

    // MARK: Events

    /// Plays a batch of events. Bubbles and tiles change at once; everything timed runs off the timeline.
    func apply(_ events: [GameEvent]) {
        guard !events.isEmpty else { return }
        let timed = Choreography.timeline(for: events, flight: flightDuration)
        var lockIDs: [String]?
        var revealIDs: Set<String> = []
        var hinted = false
        var shuffled = false
        for event in events {
            switch event {
            case let .wordLocked(_, _, ids, _, _, _, _), let .bonusCollected(_, _, _, ids):
                lockIDs = ids
            case let .wordRevealed(_, _, ids, _, _):
                revealIDs = Set(ids)
            case .hintRevealed:
                hinted = true
            case .shuffled:
                shuffled = true
            default:
                break
            }
        }
        if timed.contains(where: { $0.cue == .releaseInput }) {
            inputBlocked = true
            swipe = SwipeTracker()
        }
        syncTray(target: lockIDs ?? session.chain, revealIDs: revealIDs)
        if lockIDs == nil {
            syncScore()
            if hinted { syncSlots() }
        }
        if shuffled { layoutBoard() }

        for item in timed {
            if item.at <= 0 {
                run(item.cue)
            } else {
                timeline.append(scheduler.after(item.at) { [weak self] in self?.run(item.cue) })
            }
        }
    }

    /// `chain` is the truth, so the tray is a diff against it. During a lock the tray still shows the word's tiles.
    private func syncTray(target: [String], revealIDs: Set<String>) {
        let targetSet = Set(target)
        let current = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, $0) })
        let leaving = tiles.filter { !targetSet.contains($0.id) }.map { (tile: $0, rect: tileRect($0)) }
        let arriving = target.filter { current[$0] == nil }

        tiles = target.map { id in
            current[id] ?? TrayTile(id: id, text: session.bubble(id: id)?.text ?? "", landing: true)
        }
        layoutTiles()
        syncTrayText()

        for item in leaving {
            if revealIDs.contains(item.tile.id) {
                bubbleStates[item.tile.id]?.selected = false
            } else {
                flyHome(item.tile, from: item.rect)
            }
        }
        for id in arriving {
            bubbleStates[id]?.selected = true
            flyToTray(id)
        }
    }

    private func run(_ cue: Cue) {
        switch cue {
        case let .sound(effect):
            sound.play(effect)
        case let .haptic(haptic):
            haptics.play(haptic)
        case let .flash(flash):
            show(flash)
        case .shakeTray:
            shakeCount += 1
        case .bumpScore:
            scoreBump += 1
        case .freezeTray:
            finishAllFlights()
            trayFrozen = true
            syncTrayText()
        case let .fuseTray(tone, ids):
            fuse(tone, ids: ids)
        case let .popBubbles(ids):
            pop(ids)
        case let .commit(commit):
            self.commit(commit)
        case let .landSlot(index):
            landWord()
            if let at = slots.firstIndex(where: { $0.id == index }) { slots[at].arriving = false }
        case let .landChip(word):
            landWord()
            if arrivingChip == word { arrivingChip = nil }
        case .celebrate:
            celebrate()
        case .showResult:
            finishBoard()
        case .releaseInput:
            inputBlocked = false
        }
    }

    private func fuse(_ tone: LockTone, ids: [String]) {
        finishAllFlights()
        for index in tiles.indices { tiles[index].landing = false }
        trayFrozen = true
        lockTone = tone
        layoutTiles()
        syncTrayText()
        if tone == .accent { pop(ids) }
    }

    private func pop(_ ids: [String]) {
        for id in ids {
            guard let state = bubbleStates[id] else { continue }
            state.selected = false
            state.popping = true
        }
    }

    private func commit(_ commit: Commit) {
        let wordRect = tiles.isEmpty ? nil : tiles.map { tileRect($0) }.reduce(tileRect(tiles[0])) { $0.union($1) }
        switch commit {
        case let .word(index, word, ids, combo):
            clearTrayAfterLock()
            consume(ids)
            if let at = slots.firstIndex(where: { $0.id == index }), flightDuration > 0 { slots[at].arriving = true }
            syncScore()
            syncSlots()
            syncTabs()
            if combo >= 2 { comboBump += 1 }
            flyWord(word, tone: .accent, from: wordRect) { [weak self] in self?.slotFrames[index] }
        case let .bonus(word, tone, ids):
            clearTrayAfterLock()
            for id in ids { bubbleStates[id]?.selected = false }
            if flightDuration > 0 { arrivingChip = word }
            syncScore()
            flyWord(word, tone: tone, from: wordRect) { [weak self] in self?.chipFrames[word] }
        case let .reveal(_, ids):
            consume(ids)
            syncSlots()
            syncTabs()
        }
    }

    private func clearTrayAfterLock() {
        tiles = []
        lockTone = nil
        trayFrozen = false
        layoutTiles()
        syncTrayText()
    }

    private func consume(_ ids: [String]) {
        for id in ids {
            guard let state = bubbleStates[id] else { continue }
            state.popping = false
            state.selected = false
            state.consumed = true
        }
    }

    // MARK: Flights

    /// Adds a flight and removes it after its duration, or at once if nothing should fly.
    private func launch(_ text: String, from: CGRect?, to: CGRect?, kind: FlightKind, done: @escaping () -> Void) {
        let duration = flightDuration
        guard duration > 0, let from, let to, from.width > 0, to.width > 0 else {
            done()
            return
        }
        nextFlightID += 1
        let id = nextFlightID
        flights.append(Flight(id: id, text: text, from: from, to: to, kind: kind, duration: duration))
        flightFinishers[id] = { [weak self] in
            guard let self, self.flightFinishers.removeValue(forKey: id) != nil else { return }
            self.flights.removeAll { $0.id == id }
            done()
        }
        scheduler.after(duration) { [weak self] in self?.flightFinishers[id]?() }
    }

    private func finishAllFlights() {
        for finish in Array(flightFinishers.values) { finish() }
    }

    private func flyToTray(_ id: String) {
        guard let tile = tiles.first(where: { $0.id == id }) else { return }
        launch(tile.text, from: bubbleRect(id), to: tileRect(tile), kind: .toTray) { [weak self] in
            guard let self, let index = self.tiles.firstIndex(where: { $0.id == id }) else { return }
            self.tiles[index].landing = false
        }
    }

    private func flyHome(_ tile: TrayTile, from: CGRect) {
        let id = tile.id
        launch(tile.text, from: from, to: bubbleRect(id), kind: .toBoard) { [weak self] in
            guard let self, !self.tiles.contains(where: { $0.id == id }) else { return }
            self.bubbleStates[id]?.selected = false
        }
    }

    /// The target is read a moment later: a slot changes width when its word arrives, so it has to lay out first.
    private func flyWord(_ word: String, tone: LockTone, from: CGRect?, target: @escaping () -> CGRect?) {
        guard flightDuration > 0 else { return }
        scheduler.after(Choreography.frameLead) { [weak self] in
            self?.launch(word, from: from, to: target(), kind: .word(tone)) {}
        }
    }

    private func landWord() {
        for flight in flights {
            if case .word = flight.kind { flightFinishers[flight.id]?() }
        }
    }

    private func celebrate() {
        guard !reduceMotion(), trayFrame.width > 0 else { return }
        let origin = CGPoint(x: trayFrame.midX, y: trayFrame.midY)
        var bubbles: [CelebrationBubble] = []
        for index in 0..<12 {
            bubbles.append(CelebrationBubble(
                id: index, size: 10 + Double.random(in: 0...14),
                start: CGPoint(x: origin.x + Double.random(in: -20...20), y: origin.y),
                dx: Double.random(in: -0.45...0.45) * trayFrame.width, dy: -(80 + Double.random(in: 0...160)),
                duration: 0.7 + Double.random(in: 0...0.5)
            ))
        }
        celebration = bubbles
        scheduler.after(1.3) { [weak self] in self?.celebration = [] }
    }

    // MARK: Flash

    func show(_ flash: Flash) {
        self.flash = flash
        flashCount += 1
        flashWork?.cancel()
        flashWork = scheduler.after(Self.flashSeconds) { [weak self] in self?.clearFlash() }
    }

    private func clearFlash() {
        flashWork?.cancel()
        flashWork = nil
        flash = nil
    }

    // MARK: Timers

    func cancelTimeline() {
        timeline.forEach { $0.cancel() }
        timeline = []
    }

    func startClock() {
        clockWork?.cancel()
        clockWork = nil
        clock = session.clock
        guard isForeground, result == nil, clock != nil else { return }
        clockWork = scheduler.after(Self.clockSeconds) { [weak self] in self?.startClock() }
    }

    private func scheduleDayCheck() {
        dayWork?.cancel()
        dayWork = scheduler.after(Self.dayCheckSeconds) { [weak self] in
            self?.checkDay()
            self?.scheduleDayCheck()
        }
    }

    /// The website reloads when the date changes. Here the store rolls over and the board moves to today.
    func checkDay() {
        let today = Engine.dayNumber(for: now(), calendar: calendar)
        guard today != store.today else { return }
        store.rollover(today: today)
        open(day: today, level: store.level(forDay: today, stayingOn: level))
    }

    // MARK: Lifecycle

    func didEnterBackground() {
        guard isForeground else { return }
        isForeground = false
        session.pause()
        session.saveNow()
        store.saveNow()
        clockWork?.cancel()
        recordsWork?.cancel()
        sound.suspend()
    }

    func didBecomeActive() {
        let wasBackground = !isForeground
        isForeground = true
        if wasBackground {
            session.resume()
            sound.resume()
        }
        checkDay()
        startClock()
        if result != nil { pollRecords() }
    }

    // MARK: Navigation

    func select(level tab: Level) {
        guard !inputBlocked, tab != level else { return }
        open(day: day, level: tab)
    }

    func goToDay(_ target: Int, level explicit: Level? = nil) {
        guard !inputBlocked, target >= 1 else { return }
        let slide: SlideDirection? = target < day ? .right : target > day ? .left : nil
        open(day: target, level: explicit ?? store.level(forDay: target, stayingOn: level), slide: slide)
    }

    func previousDay() {
        if store.canGoBack(from: day) { goToDay(day - 1) }
    }

    func nextDay() {
        if store.canGoForward(from: day) { goToDay(day + 1) }
    }

    func goToToday() {
        goToDay(store.today)
    }

    func perform(_ action: ResultAction) {
        switch action {
        case let .play(targetDay, targetLevel):
            goToDay(targetDay, level: targetLevel)
        case let .switchLevel(target):
            select(level: target)
        case .share:
            break   // ShareLink handles it
        }
    }

    func openHelp() {
        overlay = .help
    }

    func openDays() {
        dayRows = store.dayRows()
        overlay = .days
    }

    func closeOverlay() {
        overlay = nil
    }

    func replayTutorial() {
        guard !inputBlocked else { return }
        overlay = nil
        open(day: store.today, level: .tutorial)
    }

    func openDayFromList(_ target: Int) {
        overlay = nil
        goToDay(target)
    }

    func toggleSound() {
        sound.isOn.toggle()
        soundOn = sound.isOn
        if soundOn { sound.play(.pick(index: 2, lift: 0)) }
    }

    // MARK: Results and records

    var boardKey: String { "\(day)-\(level.rawValue)" }

    var shareText: String {
        ShareText.make(day: day, store: store, place: place, records: allRecords)
    }

    /// Shows the card. The stars land one by one the first time only; later refreshes stay still.
    private func showResultCard() {
        resultAnimates = shownResultKey != boardKey && !isTutorial && !reduceMotion()
        if resultAnimates, case let .board(board) = makeCard() {
            for index in 0..<board.stars {
                starsWork.append(scheduler.after(0.38 + Double(index) * 0.15) { [weak self] in
                    self?.sound.play(.pick(index: 4 + index * 2, lift: 0))
                })
            }
        }
        shownResultKey = boardKey
        result = makeCard()
        pollRecords()
    }

    private func makeCard() -> ResultCard {
        ResultCard.make(day: day, level: level, store: store, place: place, records: cachedRecords)
    }

    func refreshResultCard() {
        guard result != nil else { return }
        let card = makeCard()
        if card != result { result = card }
    }

    private func finishBoard() {
        clockWork?.cancel()
        clock = session.clock
        syncHeader()
        syncScore()
        showResultCard()
        guard usesNetwork, let board = session.finishedBoard else { return }
        let finishedDay = day, finishedLevel = level
        Task { [weak self, records, place] in
            let wins = await records.submitFinish(board, place: place)
            let snapshot = await records.snapshot
            let all = await records.records
            guard let self else { return }
            self.recordsFinished(wins, day: finishedDay, level: finishedLevel, snapshot: snapshot, all: all)
        }
    }

    func recordsFinished(_ wins: RecordWins, day finishedDay: Int, level finishedLevel: Level, snapshot: [String: RecordEntry]?, all: [String: RecordEntry]) {
        let won = store.applyRecordWins(wins, day: finishedDay, level: finishedLevel)
        guard finishedDay == day, finishedLevel == level else { return }
        cachedRecords = snapshot
        allRecords = all
        refreshResultCard()
        if won { sound.play(.earn) }
    }

    private func startRecordsForBoard() {
        guard usesNetwork, !isTutorial else { return }
        refreshRecords()
    }

    private func refreshRecords() {
        guard usesNetwork, !isTutorial else { return }
        let refreshDay = day, refreshLevel = level, count = session.puzzle.bubbles.count
        Task { [weak self, records, place] in
            _ = await records.refresh(day: refreshDay, level: refreshLevel, bubbleCount: count, place: place)
            let snapshot = await records.snapshot
            let all = await records.records
            guard let self, self.day == refreshDay, self.level == refreshLevel else { return }
            self.cachedRecords = snapshot
            self.allRecords = all
            self.refreshResultCard()
        }
    }

    /// Refreshes every 30s, only while a result card is up.
    private func pollRecords() {
        recordsWork?.cancel()
        recordsWork = nil
        guard usesNetwork, isForeground, result != nil else { return }
        recordsWork = scheduler.after(Self.recordsSeconds) { [weak self] in
            guard let self, self.result != nil else { return }
            self.refreshRecords()
            self.pollRecords()
        }
    }
}
