import SwiftUI
import WordBubblesCore

/// `.preview`: the word tray and the flash line.
struct TrayView: View {
    var body: some View {
        VStack(spacing: 2) {
            TrayRow()
            FlashLine()
        }
    }
}

/// `@keyframes shake`.
struct Shake: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            let step = 0.045
            KeyframeTrack {
                LinearKeyframe(-2, duration: step)
                LinearKeyframe(4, duration: step)
                LinearKeyframe(-7, duration: step)
                LinearKeyframe(7, duration: step)
                LinearKeyframe(-7, duration: step)
                LinearKeyframe(7, duration: step)
                LinearKeyframe(-7, duration: step)
                LinearKeyframe(4, duration: step)
                LinearKeyframe(-2, duration: step)
                LinearKeyframe(0, duration: step)
            }
        }
    }
}

/// Shuffle, the tray and Hint as one piece of glass. When a word starts, the two tools flow into the tray so it has
/// the whole width. The tiles sit in their own layer so they're always laid out against that full width, whatever
/// the glass is doing.
struct TrayRow: View {
    static let height: CGFloat = 52
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        let showsTools = !model.trayActive && !model.isTutorial
        ZStack {
            GlassGroup {
                HStack(spacing: 8) {
                    if showsTools {
                        ShuffleButton()
                            .glassMorph("shuffle", in: glass)
                            .transition(.opacity)
                    }
                    TrayCapsule()
                        .glassMorph("tray", in: glass)
                    if showsTools {
                        HintButton()
                            .glassMorph("hint", in: glass)
                            .transition(.opacity)
                    }
                }
            }
            ZStack {
                TilesLayer()
                ComboBadge()
                TrayControls()
            }
            .allowsHitTesting(model.trayActive)
        }
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : Theme.glide(0.3), value: showsTools)
        .animation(reduceMotion ? nil : Theme.glide(0.3), value: model.hintArmed)
        .modifier(Shake(trigger: model.shakeCount))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GameScreen.space)) } action: { frame in
            model.trayMeasured(frame)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Word tray")
        .accessibilityIdentifier("tray")
    }
}

struct ShuffleButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        Button(action: model.shuffle) {
            Image(systemName: "shuffle")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: TrayRow.height, height: TrayRow.height)
                .floatingGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Shuffle")
        .accessibilityIdentifier("shuffle-button")
    }
}

/// While a hint would cost the medal, the first tap opens into the question and the second one answers it.
struct HintButton: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let armed = model.hintArmed
        Button(action: model.useHint) {
            Group {
                if armed {
                    Text("Lose medal?")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.onGold)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 18)
                } else {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: TrayRow.height)
                }
            }
            .frame(height: TrayRow.height)
            .floatingGlass(in: Capsule(), tint: armed ? Theme.gold1 : nil, interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(armed ? "Use hint and lose the medal" : "Hint")
        .accessibilityHint(armed ? "" : "Asks first if this would cost the medal")
        .accessibilityIdentifier("hint-button")
        .onChange(of: armed) {
            if armed {
                UIAccessibility.post(notification: .announcement, argument: "This hint costs the medal. Tap again to use it.")
            }
        }
    }
}

/// The glass of the tray, and what it says while it's empty. Heat from a combo tints it.
struct TrayCapsule: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let heat = model.heat
        ZStack {
            if !model.trayActive {
                Text(model.hintArmed ? "Tap again to confirm" : model.flash?.text ?? model.prompt)
                    .font(Theme.body(14))
                    .foregroundStyle(model.hintArmed ? Theme.muted : model.flash?.tone.color ?? Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, model.comboText == nil ? 14 : 44)
                    .transition(.opacity)
                    .accessibilityIdentifier(model.flash == nil ? "prompt" : "flash")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .floatingGlass(in: Capsule(), tint: tint(heat))
        .overlay {
            if heat > 0 { Capsule().strokeBorder(border(heat), lineWidth: 1.5) }
        }
        .animation(.easeOut(duration: 0.4), value: heat)
    }

    private func tint(_ heat: Int) -> Color? {
        switch heat {
        case 1: return Theme.accentSoft
        case 2: return Theme.hintHeatRing
        case 3...: return Theme.badSoft
        default: return nil
        }
    }

    private func border(_ heat: Int) -> Color {
        switch heat {
        case 1: return Theme.accent
        case 2: return Theme.hint
        default: return Theme.bad
        }
    }
}

/// The tiles, placed from `TrayLayout` so the flight overlay and the tray always agree.
struct TilesLayer: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
                TileView(
                    tile: tile, tone: model.lockTone, scale: model.trayScale,
                    isFirst: index == 0, isLast: index == model.tiles.count - 1
                )
            }
        }
    }
}

struct TileView: View {
    @Environment(GameModel.self) private var model
    let tile: TrayTile
    let tone: LockTone?
    let scale: Double
    let isFirst: Bool
    let isLast: Bool

    /// Capsules, concentric with the tray around them.
    private var shape: UnevenRoundedRectangle {
        let height = tile.frame.height
        guard tone != nil else {
            return UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: height / 2, bottomLeading: height / 2, bottomTrailing: height / 2, topTrailing: height / 2)
            )
        }
        let left = isFirst ? height / 2 : 0, right = isLast ? height / 2 : 0
        return UnevenRoundedRectangle(cornerRadii: .init(topLeading: left, bottomLeading: left, bottomTrailing: right, topTrailing: right))
    }

    var body: some View {
        Button {
            model.tapTile(tile.id)
        } label: {
            Text(tile.text)
                .font(Theme.display(21 * scale))
                .kerning(21 * scale * 0.02)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(tone?.ink ?? Theme.fg)
                .frame(width: tile.frame.width, height: tile.frame.height)
                .background {
                    // CSS has no transition on the fill, so a fuse is instant.
                    if let tone {
                        shape.fill(tone.verticalFill)
                    } else {
                        shape.fill(Theme.bubbleFill(size: tile.frame.size))
                            .overlay { shape.strokeBorder(Theme.bubbleBorder, lineWidth: 1) }
                            .shadow(color: RGBA(30, 45, 90, 0.12).color, radius: 5, y: 4)
                    }
                }
                .contentShape(Rectangle().inset(by: -2))
                .animation(nil, value: tone)
        }
        .buttonStyle(PressScale())
        .opacity(tile.landing ? 0 : 1)
        .position(x: tile.frame.midX, y: tile.frame.midY)
        .animation(Theme.glide(0.28), value: tile.frame)
        .accessibilityLabel("Put \(tile.text) back")
        .accessibilityIdentifier("tile-\(tile.text)")
    }
}

/// `.combo`: the "×3" badge at the tray's left end, which is further in while Shuffle is beside it.
struct ComboBadge: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let edge: CGFloat = 11

    var body: some View {
        HStack {
            if let text = model.comboText {
                let heat = model.heat
                Text(text)
                    .font(Theme.body(14))
                    .monospacedDigit()
                    .foregroundStyle(heat == 2 ? Theme.hint : heat >= 3 ? Theme.bad : Theme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(heat == 2 ? Theme.hintSoft : heat >= 3 ? Theme.badSoft : Theme.accentSoft, in: Capsule())
                    .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : model.comboBump) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.35, duration: 0.16)
                            CubicKeyframe(1, duration: 0.24)
                        }
                    }
                    .accessibilityLabel("Combo \(text.dropFirst())")
                    .accessibilityIdentifier("combo")
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, model.trayActive ? Self.edge : TrayRow.height + 8 + Self.edge)
        .animation(reduceMotion ? nil : Theme.glide(0.3), value: model.trayActive)
        .allowsHitTesting(false)
    }
}

/// Letter count, bonus button and Clear at the tray's right end.
struct TrayControls: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if model.showsLetterCount {
                Text(model.letterCountText)
                    .font(Theme.body(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .padding(.trailing, 4)
                    .accessibilityIdentifier("letter-count")
            }
            if let button = model.bonusButton {
                Button(button.label, action: model.collectBonusButton)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.hint)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Theme.hintSoft, in: Capsule())
                    .buttonStyle(PressScale())
                    .frame(minHeight: 44)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Collect bonus word")
                    .accessibilityIdentifier("bonus-button")
            }
            if model.trayActive && !model.trayFrozen {
                Button(action: model.clearTray) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 42, height: 42)
                        .background(Theme.slotBg, in: Circle())
                        .contentShape(Circle().inset(by: -2))
                }
                .buttonStyle(PressScale(amount: 0.92))
                .padding(.trailing, 5)
                .accessibilityLabel("Clear")
                .accessibilityIdentifier("clear-button")
            }
        }
    }
}

/// `.msg`: the line under the tray, for flashes while tiles fill the tray. An empty tray shows them itself.
struct FlashLine: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let flash = model.trayActive ? model.flash : nil
        Text(flash?.text ?? "")
            .font(Theme.body(12))
            .foregroundStyle(flash?.tone.color ?? Theme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .accessibilityHidden(flash == nil)
            .accessibilityIdentifier("flash-line")
            .onChange(of: model.flashCount) {
                if let text = model.flash?.text {
                    UIAccessibility.post(notification: .announcement, argument: text)
                }
            }
    }
}
