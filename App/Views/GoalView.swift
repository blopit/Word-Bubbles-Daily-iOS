import SwiftUI
import WordBubblesCore

/// `.goal`: the theme and the hidden words. Found bonus words stay off this screen until the result.
struct GoalView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            Text(model.theme)
                .font(Theme.display(compact ? 26 : 34))
                .kerning(-0.3)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("theme")
                .accessibilityAction(named: "Previous day", model.previousDay)
                .accessibilityAction(named: "Next day", model.nextDay)
            FlowLayout {
                ForEach(model.slots) { slot in
                    SlotView(display: slot)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Hidden words")
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .modifier(DaySwipe())
    }
}

struct SlotView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact
    let display: SlotDisplay

    var body: some View {
        let height: CGFloat = compact ? 28 : 34
        let fontSize: CGFloat = compact ? 14 : 16
        let padding: CGFloat = compact ? 10 : 13
        Group {
            switch display.slot {
            case let .solved(word):
                Text(word)
                    .kerning(fontSize * 0.06)
                    .foregroundStyle(Theme.onAccent)
                    .frame(height: height)
                    .padding(.horizontal, padding)
                    .background(Theme.metalGradient, in: Capsule())
            case let .hinted(text):
                Text(text)
                    .kerning(fontSize * 0.06)
                    .foregroundStyle(Theme.fg)
                    .frame(height: height)
                    .padding(.horizontal, padding)
                    .background(Theme.hintSoft, in: Capsule())
            case let .hidden(letters):
                HStack(spacing: 4) {
                    ForEach(0..<letters, id: \.self) { _ in
                        Circle().fill(Theme.slotBorder).frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
                    }
                }
                .frame(height: height)
                .padding(.horizontal, padding)
                .background(Theme.slotBg, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(letters) letters")
            }
        }
        .font(Theme.display(fontSize))
        .opacity(display.arriving ? 0 : 1)
        .modifier(PopIn(trigger: display.arriving))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GameScreen.space)) } action: { frame in
            model.slotFrames[display.id] = frame
        }
        .accessibilityIdentifier("slot-\(display.id)")
    }
}
