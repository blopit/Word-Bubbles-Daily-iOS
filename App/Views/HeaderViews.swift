import SwiftUI
import WordBubblesCore

/// The one row of chrome: the day on the left, the score in the middle, the level and everything else on the right.
struct TopBar: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        BarLayout {
            HStack(spacing: 6) {
                if model.isTutorial {
                    Brand()
                } else {
                    DayButton()
                    TodayButton()
                }
            }
            HStack(spacing: 6) {
                if !model.isTutorial {
                    LevelMenu()
                    MoreMenu()
                } else if model.result == nil {
                    SkipButton()
                }
            }
            if !model.isTutorial, model.result == nil {
                ScoreHUD()
            }
        }
        .animation(Theme.glide(0.3), value: model.showsToday)
        .frame(height: 44)
    }
}

/// Leading and trailing groups at the edges, and an optional third view centered on the bar. When the leading group
/// grows into it (the Today button on an earlier day), the center view moves right into the middle of the gap left.
struct BarLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 358, height: 44)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[1].sizeThatFits(.unspecified)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(leading))
        subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(trailing))
        guard subviews.count > 2 else { return }
        let center = subviews[2].sizeThatFits(.unspecified)
        let low = bounds.minX + leading.width + spacing + center.width / 2
        let high = bounds.maxX - trailing.width - spacing - center.width / 2
        let x = low > bounds.midX ? (low + high) / 2 : bounds.midX
        subviews[2].place(at: CGPoint(x: x, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(center))
    }
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            GlossyCircle(diameter: 22)
                .accessibilityHidden(true)
            Text("Word Bubbles")
                .font(Theme.display(20))
                .kerning(-0.2)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct SkipButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        Button("Skip", action: model.skipTutorial)
            .font(Theme.body(15))
            .padding(.horizontal, 18)
            .frame(height: 44)
            .floatingGlass(in: Capsule(), interactive: true)
            .buttonStyle(PressScale())
            .accessibilityLabel("Skip tutorial")
            .accessibilityIdentifier("skip-tutorial")
    }
}

/// Opens the calendar. Shrinks to its icon while a word is being spelled.
struct DayButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let spelling = model.trayActive
        Button(action: model.openDays) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 16, weight: .semibold))
                if !spelling {
                    Text(model.dayTitle)
                        .font(Theme.body(15))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, spelling ? 0 : 14)
            .frame(minWidth: 44, minHeight: 44)
            .floatingGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .animation(Theme.glide(0.3), value: spelling)
        .accessibilityLabel("\(model.dayName), \(model.dayLabel). Your days")
        .accessibilityIdentifier("days-button")
    }
}

/// The way home from an earlier day, beside the calendar. Steps aside while a word is being spelled.
struct TodayButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        if model.showsToday, !model.trayActive {
            Button("Today", action: model.goToToday)
                .font(Theme.body(15))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .floatingGlass(in: Capsule(), interactive: true)
                .contentShape(Capsule())
                .buttonStyle(PressScale())
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Back to Today")
                .accessibilityIdentifier("today-button")
        }
    }
}

/// Settings live here, in a native menu that stays open while they change.
struct MoreMenu: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        Menu {
            Toggle("Sound", systemImage: "speaker.wave.2", isOn: Binding(
                get: { model.soundOn }, set: { _ in model.toggleSound() }
            ))
            .menuActionDismissBehavior(.disabled)
            Toggle("Haptics", systemImage: "iphone.radiowaves.left.and.right", isOn: Binding(
                get: { model.hapticsOn }, set: model.setHaptics
            ))
            .menuActionDismissBehavior(.disabled)
            Toggle("Post Times to Leaderboards", systemImage: "trophy", isOn: Binding(
                get: { model.postsTimes }, set: model.setPostsTimes
            ))
            .menuActionDismissBehavior(.disabled)
            Divider()
            Button("How to Play", systemImage: "questionmark.circle", action: model.openHelp)
                .accessibilityIdentifier("help-button")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .floatingGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("more-menu")
    }
}

/// The levels, in a glass dropdown beside "⋯". The button wears the current level's symbol, and the menu shows each
/// level's progress. Locked while a word is being spelled, so a stray thumb can't change level.
struct LevelMenu: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        Menu {
            Picker("Difficulty", selection: Binding(get: { model.level }, set: model.select(level:))) {
                ForEach(model.tabs) { tab in
                    Label(tab.badge.isEmpty ? tab.level.label : "\(tab.level.label)  \(tab.badge)", systemImage: tab.level.symbol)
                        .tag(tab.level)
                        .accessibilityIdentifier("tab-\(tab.level.rawValue)")
                }
            }
        } label: {
            Image(systemName: model.level.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.level.tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .floatingGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .disabled(model.trayActive)
        .accessibilityLabel("Difficulty, \(model.level.label)")
        .accessibilityIdentifier("level-menu")
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
