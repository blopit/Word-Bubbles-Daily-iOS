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

/// `.overlay`: dim, tap outside to close, the card rising in.
struct OverlayHost: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let overlay = model.overlay {
                Theme.dim
                    .ignoresSafeArea()
                    .onTapGesture(perform: model.closeOverlay)
                    .accessibilityLabel("Close")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("overlay-dim")
                    .transition(.opacity)
                Group {
                    switch overlay {
                    case .help: HelpCard()
                    case .days: DaysCard()
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .offset(y: 10)))
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.overlay)
    }
}

/// `.card`.
struct CardShell<Content: View>: View {
    @Environment(GameModel.self) private var model
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14, content: content)
                .padding(.vertical, 22)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            CloseButton()
        }
        .frame(maxWidth: 400)
        .glassCard()
    }
}

struct CloseButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        Button(action: model.closeOverlay) {
            Text("×")
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.muted)
                .frame(width: 40, height: 40)
                .background(Theme.slotBg, in: Circle())
                .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(PressScale(amount: 0.92))
        .padding(12)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("card-close")
    }
}

extension View {
    /// The site's frosted card: `backdrop-filter: blur`, glass tint, hairline and soft shadow.
    func glassCard() -> some View {
        background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                // System materials lift dark backgrounds to grey; the page color keeps the card the site's navy.
                .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.bg.opacity(0.78)) }
                .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.glassStrong) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1) }
        .cssShadow(RoundedRectangle(cornerRadius: 26, style: .continuous), color: Theme.glassShadow, blur: 32, y: 12)
    }
}

/// How to play.
struct HelpCard: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        CardShell {
            Text(GameText.Help.title)
                .font(Theme.display(24))
                .accessibilityAddTraits(.isHeader)
                .padding(.trailing, 44)
            ViewThatFits(in: .vertical) {
                steps
                ScrollView { steps }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicatorsFlash(onAppear: true)
            }
            HStack(spacing: 10) {
                ResultStyleButton(title: GameText.Help.replayTutorial, style: .secondary, id: "replay-tutorial", action: model.replayTutorial)
                ResultStyleButton(title: GameText.Help.close, style: .primary, id: "help-close", action: model.closeOverlay)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(GameText.Help.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).").monospacedDigit().frame(minWidth: 16, alignment: .trailing)
                        styled(step, bold: Theme.fg, secret: Theme.secretInk, plain: Theme.fg)
                            .fontWeight(.bold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.body(15, weight: .semibold))
                    .lineSpacing(2)
                    .accessibilityElement(children: .combine)
                }
            }
            demo
            Text(GameText.Help.footnote)
                .font(Theme.body(14, weight: .bold))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

/// Your days.
struct DaysCard: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        CardShell {
            Text(GameText.Days.title)
                .font(Theme.display(24))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                let stats = model.store.stats
                let values = [stats.days, stats.streak, stats.best, stats.perfect]
                ForEach(Array(GameText.Days.statLabels.enumerated()), id: \.offset) { index, label in
                    VStack(spacing: 0) {
                        Text("\(values[index])")
                            .font(Theme.display(26))
                            .monospacedDigit()
                        Text(label.uppercased())
                            .font(Theme.body(11))
                            .kerning(0.66)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
            CountdownText()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(model.dayRows, id: \.day) { row in
                        DayRowView(row: row)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("day-list")
            Text(GameText.Days.footnote)
                .font(Theme.body(13, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct DayRowView: View {
    @Environment(GameModel.self) private var model
    let row: DayRow

    private func dot(_ level: Level) -> some View {
        let done = row.done.contains(level)
        let color: Color = level == .easy ? Theme.good : level == .medium ? Theme.hint : Theme.bad
        return Circle()
            .fill(done ? color : .clear)
            .overlay { if !done { Circle().strokeBorder(Theme.slotBorder, lineWidth: 2) } }
            .frame(width: 11, height: 11)
    }

    var body: some View {
        let open = row.done.count < Level.playable.count
        HStack(spacing: 10) {
            Text(model.formatter.short(day: row.day))
                .font(Theme.body(15))
                .frame(minWidth: 54, alignment: .leading)
            Text(model.formatter.relative(day: row.day, today: model.store.today))
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 64, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(Level.playable, id: \.self) { dot($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.openDayFromList(row.day)
            } label: {
                Text(row.buttonLabel)
                    .font(Theme.body(13))
                    .foregroundStyle(open ? Theme.onAccent : Theme.fg)
                    .frame(height: 40)
                    .padding(.horizontal, 14)
                    .background {
                        if open {
                            Capsule().fill(Theme.accentVertical)
                        } else {
                            Capsule().fill(Theme.glass).overlay { Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1) }
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("\(row.buttonLabel) \(model.formatter.full(day: row.day))")
            .accessibilityIdentifier("day-row-\(row.day)")
        }
        .monospacedDigit()
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8))
        .background(Theme.slotBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if row.day == model.day { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 2) }
        }
    }
}

/// "New boards in 9h 05m", kept current.
struct CountdownText: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(GameText.countdown(now: context.date))
                .font(Theme.body(13))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("countdown")
        }
    }
}
