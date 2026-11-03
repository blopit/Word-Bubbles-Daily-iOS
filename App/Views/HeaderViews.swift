import SwiftUI
import WordBubblesCore

/// The one row of chrome: the day on the left, the score in the middle, everything else behind "⋯".
struct TopBar: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if model.isTutorial { Brand() } else { DayButton() }
                Spacer(minLength: 8)
                if !model.isTutorial {
                    MoreMenu()
                } else if model.result == nil {
                    SkipButton()
                }
            }
            if !model.isTutorial, model.result == nil {
                ScoreHUD()
            }
        }
        .frame(height: 44)
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

/// The levels, as a floating bar like a system tab bar. While a word is being spelled it draws in to the current
/// level, so the board has the screen and a stray thumb can't change level.
struct LevelBar: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let height: CGFloat = 52
    private static let inset: CGFloat = 4

    var body: some View {
        let index = CGFloat(Level.playable.firstIndex(of: model.level) ?? 0)
        let spelling = model.trayActive
        GeometryReader { proxy in
            let full = proxy.size.width
            let segment = (full - Self.inset * 2) / 3
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.glassStrong)
                    .shadow(color: RGBA(20, 30, 60, 0.12).color, radius: 5, y: 2)
                    .frame(width: segment, height: Self.height - Self.inset * 2)
                    .offset(x: Self.inset + index * segment)
                    .animation(Theme.settle(0.32), value: index)
                HStack(spacing: 0) {
                    ForEach(model.tabs) { tab in
                        tabButton(tab, spelling: spelling).frame(width: segment)
                    }
                }
                .padding(.horizontal, Self.inset)
            }
            .frame(width: full, height: Self.height, alignment: .leading)
            .offset(x: spelling ? -index * segment : 0)
            .frame(width: spelling ? segment + Self.inset * 2 : full, height: Self.height, alignment: .leading)
            .clipShape(Capsule())
            .floatingGlass(in: Capsule())
            .frame(width: full)
        }
        .frame(height: Self.height)
        .padding(.horizontal, 4)
        .animation(reduceMotion ? nil : Theme.glide(0.35), value: spelling)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Difficulty")
    }

    private func tabButton(_ tab: TabDisplay, spelling: Bool) -> some View {
        let active = tab.level == model.level
        return Button {
            model.select(level: tab.level)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tab.level.tint).frame(width: 7, height: 7)
                Text(tab.level.label)
                if !tab.badge.isEmpty {
                    Text(tab.badge).font(Theme.body(11)).monospacedDigit().foregroundStyle(Theme.good)
                }
            }
            .font(Theme.body(14))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(active ? Theme.fg : Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.2), value: active)
        }
        .buttonStyle(PressScale())
        .opacity(spelling && !active ? 0 : 1)
        .allowsHitTesting(!spelling)
        .accessibilityHidden(spelling && !active)
        .accessibilityLabel(tab.level.label + (tab.badge == "✓" ? ", done" : tab.badge.isEmpty ? "" : ", \(tab.badge)"))
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("tab-\(tab.level.rawValue)")
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
