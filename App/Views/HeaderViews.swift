import SwiftUI
import WordBubblesCore

/// A round panel button, 40pt with a 44pt target.
struct IconButton<Label: View>: View {
    var size: CGFloat = 40
    let accessibility: String
    let identifier: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .background(Theme.panel, in: Circle())
                .overlay { Circle().strokeBorder(Theme.glassBorder, lineWidth: 1) }
                .cssShadow(Circle(), color: Theme.glassShadow, blur: 32, y: 12)
                .frame(width: max(size, 44), height: max(size, 44))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(accessibility)
        .accessibilityIdentifier(identifier)
    }
}

/// `.top`.
struct TopBar: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                GlossyCircle(diameter: 22)
                    .accessibilityHidden(true)
                Text("Word Bubbles")
                    .font(Theme.display(20))
                    .kerning(-0.2)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                IconButton(
                    accessibility: model.soundOn ? "Sound on" : "Sound off", identifier: "sound-button",
                    action: model.toggleSound
                ) {
                    Image(systemName: model.soundOn ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size: 15, weight: .semibold))
                }
                IconButton(accessibility: "Days and statistics", identifier: "days-button", action: model.openDays) {
                    Image(systemName: "calendar").font(.system(size: 16, weight: .semibold))
                }
                IconButton(accessibility: "How to play", identifier: "help-button", action: model.openHelp) {
                    Text("?").font(Theme.body(16))
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(minHeight: compact ? 40 : nil)
    }
}

/// `.tabs`: a pill with a sliding thumb.
struct LevelTabs: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact

    private func dot(_ level: Level) -> Color {
        switch level {
        case .easy: return Theme.good
        case .medium: return Theme.hint
        case .hard: return Theme.bad
        case .tutorial: return Theme.muted
        }
    }

    var body: some View {
        let index = Level.playable.firstIndex(of: model.level) ?? 0
        GeometryReader { proxy in
            let width = (proxy.size.width - 6) / 3
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.glassStrong)
                    .shadow(color: RGBA(20, 30, 60, 0.12).color, radius: 5, y: 2)
                    .frame(width: width)
                    .padding(.vertical, 3)
                    .offset(x: 3 + CGFloat(index) * width)
                    .animation(Theme.settle(0.32), value: index)
                HStack(spacing: 0) {
                    ForEach(model.tabs) { tab in
                        tabButton(tab).frame(width: width)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
        .frame(height: compact ? 40 : 44)
        .background(Theme.panel, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1) }
        .cssShadow(Capsule(), color: Theme.glassShadow, blur: 32, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Difficulty")
    }

    private func tabButton(_ tab: TabDisplay) -> some View {
        let active = tab.level == model.level
        return Button {
            model.select(level: tab.level)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(dot(tab.level)).frame(width: 7, height: 7)
                Text(tab.level.label)
                if !tab.badge.isEmpty {
                    Text(tab.badge).font(Theme.body(11)).monospacedDigit().foregroundStyle(Theme.good)
                }
            }
            .font(Theme.body(14))
            .foregroundStyle(active ? Theme.fg : Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: compact ? -2 : 0))
            .animation(.easeOut(duration: 0.2), value: active)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(tab.level.label + (tab.badge == "✓" ? ", done" : tab.badge.isEmpty ? "" : ", \(tab.badge)"))
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("tab-\(tab.level.rawValue)")
    }
}

/// `.daynav`.
struct DayNav: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                navButton("‹", label: "Previous day", id: "prev-day", enabled: model.canGoBack, action: model.previousDay)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.dayName).font(Theme.body(15))
                    Text(model.dayLabel).font(Theme.body(13)).foregroundStyle(Theme.muted)
                }
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 170)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("day-label")
                navButton("›", label: "Next day", id: "next-day", enabled: model.canGoForward, action: model.nextDay)
            }
            .frame(maxWidth: .infinity)
            if model.showsToday {
                Button("Today", action: model.goToToday)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("today-button")
            }
        }
    }

    private func navButton(_ glyph: String, label: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let size: CGFloat = compact ? 40 : 44
        return Button(action: action) {
            Text(glyph)
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 2)
                .frame(width: size, height: size)
                .background(Theme.panel, in: Circle())
                .overlay { Circle().strokeBorder(Theme.glassBorder, lineWidth: 1) }
                .frame(width: 44, height: size)
                .contentShape(Rectangle().inset(by: size - 44 < 0 ? -2 : 0))
        }
        .buttonStyle(PressScale(amount: 0.92))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Lays children in centered, wrapping rows: the site's `flex-wrap` with `justify-content: center`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 358
        let all = rows(subviews, width: width)
        let height = all.reduce(0) { $0 + ($1.map(\.size.height).max() ?? 0) } + lineSpacing * CGFloat(max(all.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let total = row.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(row.count - 1, 0))
            var x = bounds.minX + (bounds.width - total) / 2
            let height = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += height + lineSpacing
        }
    }
}
