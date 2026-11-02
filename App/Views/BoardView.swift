import SwiftUI
import WordBubblesCore

/// `.board`: the honeycomb. One drag gesture over the whole board feeds `SwipeTracker`, for taps and swipes alike.
struct BoardView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let diameter = model.diameter
        ZStack(alignment: .topLeading) {
            Color.clear
            if diameter > 0 {
                let sprite = BubbleSprite.image(diameter: diameter, scheme: scheme, scale: displayScale)
                ForEach(Array(model.bubbles.enumerated()), id: \.element.id) { index, bubble in
                    if let state = model.bubbleStates[bubble.id] {
                        BubbleView(
                            bubble: bubble, state: state, index: index, sprite: sprite,
                            diameter: diameter, fontSize: model.fontSize
                        )
                    }
                }
                .id(model.boardGeneration)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    model.touch(at: value.location)
                }
                .onEnded { _ in model.touchEnded() }
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GameScreen.space)) } action: { frame in
            model.boardMeasured(frame)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letter bubbles")
    }
}

/// `.bub`. Reads only its own `BubbleState`, so a pick redraws one bubble.
struct BubbleView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bubble: Bubble
    let state: BubbleState
    let index: Int
    let sprite: Image
    let diameter: CGFloat
    let fontSize: CGFloat
    @State private var entered = false

    private var scale: CGFloat {
        state.popping ? 0.5 : state.selected ? 0.84 : 1
    }

    private var alpha: Double {
        state.popping ? 0 : state.selected ? 0.3 : 1
    }

    var body: some View {
        if !state.consumed {
            let outer = diameter + BubbleSprite.margin * 2
            ZStack {
                sprite
                    .resizable()
                    .frame(width: outer, height: outer)
                if state.hintNumber != nil {
                    Circle()
                        .strokeBorder(Theme.hint, lineWidth: 3)
                        .frame(width: diameter + 6, height: diameter + 6)
                        .shadow(color: Theme.hintRing, radius: 11, y: 10)
                }
                Text(bubble.text)
                    .font(Theme.display(fontSize))
                    .kerning(fontSize * 0.02)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Theme.fg)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .overlay(alignment: .topTrailing) {
                if let number = state.hintNumber {
                    Text("\(number)")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.badgeInk)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Theme.hint, in: Capsule())
                        .offset(x: 3, y: -5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bubble " + bubble.text.map(String.init).joined(separator: " "))
            .accessibilityValue(state.hintNumber.map { "Hint \($0)" } ?? "")
            .accessibilityAddTraits(state.selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.activateBubble(bubble.id) }
            .accessibilityIdentifier("bubble-\(bubble.text)")
            .scaleEffect(scale)
            .opacity(alpha)
            .animation(Theme.glide(0.25), value: state.selected)
            .animation(Theme.glide(0.25), value: state.popping)
            .scaleEffect(entered ? 1 : 0.4)
            .opacity(entered ? 1 : 0)
            .position(state.point)
            .animation(Theme.settle(0.45), value: state.point)
            .onAppear {
                guard !entered else { return }
                if reduceMotion {
                    entered = true
                } else {
                    withAnimation(Theme.popCurve(0.45).delay(Double(index) * 0.03)) { entered = true }
                }
            }
        }
    }
}
