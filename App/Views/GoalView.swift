import SwiftUI
import WordBubblesCore

/// `.goal`: theme, word slots and the bonus strip.
struct GoalView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact

    var body: some View {
        VStack(spacing: 4) {
            Text(model.theme)
                .font(Theme.display(compact ? 21 : 26))
                .kerning(-0.2)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("theme")
            FlowLayout {
                ForEach(model.slots) { slot in
                    SlotView(display: slot)
                }
            }
            .padding(.top, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Hidden words")
            if let chips = model.bonusChips, !chips.isEmpty {
                BonusBar(chips: chips)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SlotView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact
    let display: SlotDisplay

    var body: some View {
        let height: CGFloat = compact ? 26 : 30
        let fontSize: CGFloat = compact ? 13 : 15
        Group {
            switch display.slot {
            case let .solved(word):
                Text(word)
                    .kerning(fontSize * 0.06)
                    .foregroundStyle(Theme.onAccent)
                    .frame(height: height)
                    .padding(.horizontal, compact ? 9 : 11)
                    .background(Theme.metalGradient, in: Capsule())
            case let .hinted(text):
                Text(text)
                    .kerning(fontSize * 0.06)
                    .foregroundStyle(Theme.fg)
                    .frame(height: height)
                    .padding(.horizontal, compact ? 9 : 11)
                    .overlay { Capsule().strokeBorder(Theme.hint, lineWidth: 1.5) }
            case let .hidden(letters):
                HStack(spacing: 4) {
                    ForEach(0..<letters, id: \.self) { _ in
                        Circle().fill(Theme.slotBorder).frame(width: 6, height: 6)
                    }
                }
                .frame(height: height)
                .padding(.horizontal, compact ? 9 : 11)
                .overlay {
                    Capsule().strokeBorder(Theme.slotBorder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
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

/// `.bonusbar`: gold and purple chips, newest first.
struct BonusBar: View {
    @Environment(GameModel.self) private var model
    let chips: [BonusChip]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(chips, id: \.word) { chip in
                    Text(chip.word)
                        .font(Theme.display(13))
                        .kerning(13 * 0.06)
                        .foregroundStyle(chip.isSecret ? Theme.onSecret : Theme.onGold)
                        .frame(height: 26)
                        .padding(.horizontal, 10)
                        .background(chip.isSecret ? Theme.secretDiagonal : Theme.goldDiagonal, in: Capsule())
                        .opacity(model.arrivingChip == chip.word ? 0 : 1)
                        .modifier(PopIn(trigger: model.arrivingChip == chip.word))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GameScreen.space)) } action: { frame in
                            model.chipFrames[chip.word] = frame
                        }
                        .accessibilityIdentifier("bonus-chip-\(chip.word)")
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bonus words found")
    }
}
