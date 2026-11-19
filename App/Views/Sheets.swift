import SwiftUI
import WordBubblesCore

/// Text with the site's `<b>` and secret coloring.
func styled(_ segments: [TextSegment], bold: Color, secret: Color, plain: Color) -> Text {
    segments.reduce(Text("")) { text, segment in
        switch segment {
        case let .plain(string):
            return text + Text(string).foregroundColor(plain)
        case let .bold(string):
            return text + Text(string).foregroundColor(bold)
        case let .secret(string):
            return text + Text(string).foregroundColor(secret)
        }
    }
}

/// Sheet chrome shared by help and the calendar: a title, a Done button and two heights.
private struct SheetFrame<Content: View, Leading: View>: View {
    let title: String
    let doneID: String
    let close: () -> Void
    /// The heights the sheet can take, starting at the first.
    let detents: [PresentationDetent]
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let content: () -> Content
    @State private var detent: PresentationDetent

    init(
        title: String, doneID: String, close: @escaping () -> Void, detents: [PresentationDetent] = [.medium, .large],
        @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.doneID = doneID
        self.close = close
        self.detents = detents
        self.leading = leading
        self.content = content
        _detent = State(initialValue: detents[0])
    }

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading, content: leading)
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: close).accessibilityIdentifier(doneID)
                    }
                }
        }
        .presentationDetents(Set(detents), selection: $detent)
        .presentationDragIndicator(.visible)
        .foregroundStyle(Theme.fg)
    }
}

/// How to play, as something you can skim: one idea per row.
struct HelpSheet: View {
    @Environment(GameModel.self) private var model

    private struct Row: Identifiable {
        var id: String { title }
        let symbol: String
        let title: String
        let detail: String
    }

    private static let rows = [
        Row(symbol: "hand.draw", title: "Spell the hidden words", detail: "Swipe or tap bubbles in order. They click into place when they make a word."),
        Row(symbol: "flame", title: "Build a combo", detail: "Hidden words in a row multiply your score, up to ×4. Putting a bubble back or using a hint starts it over."),
        Row(symbol: "sparkles", title: "Find bonus words", detail: "Any other real word scores too, and one that fits the theme is a secret worth five times more. See them all on the score screen. Find them early: a hidden word uses its bubbles up."),
        Row(symbol: "timer", title: "Race the clock", detail: "A quick finish wins bronze, silver or gold. A hint gives up the medal and any record, so it asks first."),
        Row(symbol: "shuffle", title: "Stuck?", detail: "Shuffle re-deals the bubbles for free."),
        Row(symbol: "calendar", title: "Three new boards a day", detail: "Easy, Medium and Hard arrive at midnight. The last week stays open from the calendar, and Word Bubbles+ opens the whole past year."),
    ]

    var body: some View {
        SheetFrame(title: GameText.Help.title, doneID: "help-close", close: model.closeOverlay) {
            EmptyView()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    demo
                    ForEach(Self.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Image(systemName: row.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(Theme.text(.headline))
                                Text(row.detail)
                                    .font(Theme.text(.subheadline, weight: .regular))
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Finish times post anonymously, with a rough region from your time zone. Turn this off in the ⋯ menu.")
                        .font(Theme.text(.footnote, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(GameText.Help.replayTutorial, action: model.replayTutorial)
                        .font(Theme.text(.subheadline))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("replay-tutorial")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var demo: some View {
        HStack(spacing: 8) {
            ForEach(Array(GameText.Help.demoChunks.enumerated()), id: \.offset) { index, chunk in
                if index > 0 { Text("→").font(Theme.body(14)).foregroundStyle(Theme.muted) }
                ZStack {
                    GlossyCircle(diameter: 46)
                    Text(chunk).font(Theme.display(14))
                }
            }
            Text("=").font(Theme.body(14)).foregroundStyle(Theme.muted)
            Text(GameText.Help.demoWord)
                .font(Theme.display(13))
                .kerning(13 * 0.04)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.onAccent)
                .frame(height: 30)
                .padding(.horizontal, 9)
                .background(Theme.metalGradient, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// Your days: the stats, and a calendar you scroll back through. Each day's ring has an arc per board.
struct CalendarSheet: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let months = CalendarMonth.months(today: model.store.today, rows: model.dayRows, calendar: .current)
        let weekdays = CalendarMonth.weekdays(calendar: .current)
        // Opens tall enough for the whole current month, so none of it starts out under the stats.
        SheetFrame(
            title: GameText.Days.title, doneID: "card-close", close: model.closeOverlay, detents: [.large, .medium]
        ) {
            if model.showsToday {
                Button("Today") { model.openDayFromList(model.store.today) }
                    .accessibilityIdentifier("calendar-today")
            }
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(months) { month in
                        MonthGrid(month: month)
                    }
                    Text(GameText.Days.footnote)
                        .font(Theme.text(.footnote, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .pinnedTopBar {
                // The weekday letters are the same for every month, so they stay put with the stats.
                VStack(spacing: 10) {
                    DayStats()
                    LazyVGrid(columns: MonthGrid.columns, spacing: 0) {
                        ForEach(Array(weekdays.enumerated()), id: \.offset) { _, letter in
                            Text(letter)
                                .font(Theme.text(.caption2))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct DayStats: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let stats = model.store.stats
        let values = [stats.days, stats.streak, stats.best, stats.perfect]
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(GameText.Days.statLabels.enumerated()), id: \.offset) { index, label in
                    VStack(spacing: 0) {
                        Text("\(values[index])")
                            .font(Theme.text(.title2, weight: .bold))
                            .monospacedDigit()
                        Text(label)
                            .font(Theme.text(.caption))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            CountdownText()
        }
    }
}

private struct MonthGrid: View {
    let month: CalendarMonth
    static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(month.title)
                .font(Theme.text(.headline))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 1).accessibilityHidden(true)
                }
                ForEach(month.cells) { cell in
                    DayCell(cell: cell)
                }
            }
        }
    }
}

private struct DayCell: View {
    @Environment(GameModel.self) private var model
    private static let size: CGFloat = 44
    let cell: CalendarMonth.Cell

    var body: some View {
        let isToday = cell.day == model.store.today
        let isViewed = cell.day == model.day
        let locked = cell.isPlayable && model.isLocked(day: cell.day)
        Button {
            model.openDayFromList(cell.day)
        } label: {
            ZStack {
                if isViewed { Circle().fill(Theme.accentSoft).padding(2) }
                if cell.isPlayable { DayRing(done: cell.done) }
                Text("\(cell.date)")
                    .font(Theme.text(.footnote, weight: isToday ? .heavy : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Theme.accent : Theme.fg)
                    .minimumScaleFactor(0.7)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .offset(y: 13)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(amount: 0.9))
        .disabled(!cell.isPlayable)
        .opacity(!cell.isPlayable ? 0.3 : locked ? 0.6 : 1)
        .accessibilityLabel(locked
            ? "\(model.formatter.full(day: cell.day)), needs Word Bubbles+"
            : "\(model.formatter.full(day: cell.day)), \(cell.done.count) of 3 boards done")
        .accessibilityIdentifier("day-row-\(cell.day)")
    }
}

/// One arc for each of the day's boards, in the level's color once finished.
private struct DayRing: View {
    let done: [Level]
    private static let gap = 0.035

    var body: some View {
        ZStack {
            ForEach(Array(Level.playable.enumerated()), id: \.offset) { index, level in
                let finished = done.contains(level)
                Circle()
                    .trim(from: Double(index) / 3 + Self.gap, to: Double(index + 1) / 3 - Self.gap)
                    .stroke(finished ? level.tint : Theme.slotBg, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(3)
    }
}

/// "New boards in 9h 05m", kept current.
struct CountdownText: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(GameText.countdown(now: context.date))
                .font(Theme.text(.footnote))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("countdown")
        }
    }
}

/// Word Bubbles+: what it opens, the one price, and a way to restore it.
struct PlusSheet: View {
    @Environment(GameModel.self) private var model
    @Environment(PlusStore.self) private var plus

    private static let rows = [
        (symbol: "calendar", title: "Every day of the past year", detail: "Open any board in the calendar, not just this week's."),
        (symbol: "arrow.uturn.backward", title: "Catch up anytime", detail: "Missed a few days? Play every Easy, Medium and Hard you skipped."),
        (symbol: "heart", title: "Keep Word Bubbles going", detail: "It's made by one person, with no ads and no tracking."),
    ]

    var body: some View {
        SheetFrame(title: "", doneID: "plus-close", close: model.closeOverlay) {
            EmptyView()
        } content: {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        GlossyCircle(diameter: 54).accessibilityHidden(true)
                        Text("Word Bubbles+")
                            .font(Theme.display(26))
                            .accessibilityAddTraits(.isHeader)
                        Text(model.wantedDay == nil ? "Today and the last week are free." : "This day is more than a week old.")
                            .font(Theme.text(.subheadline, weight: .regular))
                            .foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Self.rows, id: \.title) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Image(systemName: row.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).font(Theme.text(.headline))
                                    Text(row.detail)
                                        .font(Theme.text(.subheadline, weight: .regular))
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if plus.isUnlocked {
            Label("Every day is open. Thank you!", systemImage: "checkmark.seal.fill")
                .font(Theme.text(.headline))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("plus-owned")
        } else {
            VStack(spacing: 10) {
                Button {
                    Task { await plus.purchase() }
                } label: {
                    GlassActionLabel(title: plus.price.map { "Unlock for \($0)" } ?? "Unlock", systemImage: "lock.open", prominent: true)
                }
                .buttonStyle(PressScale(amount: 0.96))
                .disabled(plus.status == .working)
                .accessibilityIdentifier("plus-buy")
                Text("One-time purchase. No subscription.")
                    .font(Theme.text(.footnote, weight: .regular))
                    .foregroundStyle(Theme.muted)
                if let message {
                    Text(message)
                        .font(Theme.text(.footnote))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("plus-status")
                }
                Button("Restore Purchase") {
                    Task { await plus.restore() }
                }
                .font(Theme.text(.subheadline))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
                .disabled(plus.status == .working)
                .accessibilityIdentifier("plus-restore")
            }
        }
    }

    private var message: String? {
        switch plus.status {
        case .idle: return nil
        case .working: return "Talking to the App Store…"
        case .pending: return "Waiting for approval. Every day opens as soon as it's approved."
        case let .failed(text): return text
        }
    }
}
