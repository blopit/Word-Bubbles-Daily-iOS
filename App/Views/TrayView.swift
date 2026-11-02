import SwiftUI
import WordBubblesCore

/// `.preview`: the word tray and the flash line.
struct TrayView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact

    var body: some View {
        VStack(spacing: 2) {
            TrayPill()
                .frame(height: compact ? 48 : 52)
                .modifier(Shake(trigger: model.shakeCount))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GameScreen.space)) } action: { frame in
                    model.trayMeasured(frame)
                }
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

struct TrayPill: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ZStack {
            PillBackground()
            if !model.trayActive {
                Text(model.prompt)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 18)
            }
            TilesLayer()
            ComboBadge()
            TrayControls()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Word tray")
        .accessibilityIdentifier("tray")
    }
}

struct PillBackground: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        let heat = model.heat
        Capsule()
            .fill(Theme.panel)
            .overlay { Capsule().strokeBorder(borderColor(heat), lineWidth: 1) }
            .background {
                if heat > 0 { Capsule().stroke(ringColor(heat), lineWidth: heat == 1 ? 6 : 8) }
            }
            .cssShadow(Capsule(), color: shadowColor(heat), blur: shadowRadius(heat) * 2, y: heat >= 3 ? 12 : heat == 2 ? 10 : 12)
            .animation(.easeOut(duration: 0.4), value: heat)
            .accessibilityHidden(true)
    }

    private func borderColor(_ heat: Int) -> Color {
        switch heat {
        case 1: return Theme.accent
        case 2: return Theme.hint
        case 3: return Theme.bad
        default: return Theme.glassBorder
        }
    }

    private func ringColor(_ heat: Int) -> Color {
        switch heat {
        case 1: return Theme.accentSoft
        case 2: return Theme.hintHeatRing
        default: return Theme.badSoft
        }
    }

    private func shadowColor(_ heat: Int) -> Color {
        switch heat {
        case 2: return Theme.hintHeatGlow
        case 3: return Theme.badHeatGlow
        default: return Theme.glassShadow
        }
    }

    private func shadowRadius(_ heat: Int) -> CGFloat {
        heat >= 3 ? 17 : heat == 2 ? 15 : 16
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

    private var shape: UnevenRoundedRectangle {
        let height = tile.frame.height
        guard tone != nil else {
            return UnevenRoundedRectangle(cornerRadii: .init(topLeading: 12, bottomLeading: 12, bottomTrailing: 12, topTrailing: 12))
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

/// `.combo`: the "×3" badge at the tray's left end.
struct ComboBadge: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .padding(.leading, 8)
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
                    Text("×")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 40, height: 40)
                        .background(Theme.slotBg, in: Circle())
                        .contentShape(Circle().inset(by: -2))
                }
                .buttonStyle(PressScale(amount: 0.92))
                .padding(.trailing, 6)
                .accessibilityLabel("Clear")
                .accessibilityIdentifier("clear-button")
            }
        }
    }
}

/// `.msg`: one line that shows a flash for 1.9s, tall enough to stay put while empty.
struct FlashLine: View {
    @Environment(GameModel.self) private var model

    private func color(_ tone: FlashTone?) -> Color {
        switch tone {
        case .good: return Theme.good
        case .hint: return Theme.hint
        case .bad: return Theme.bad
        case .secret: return Theme.secretInk
        case nil: return Theme.muted
        }
    }

    var body: some View {
        Text(model.flash?.text ?? "")
            .font(Theme.body(12))
            .foregroundStyle(color(model.flash?.tone))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .accessibilityIdentifier("flash")
            .onChange(of: model.flashCount) {
                if let text = model.flash?.text {
                    UIAccessibility.post(notification: .announcement, argument: text)
                }
            }
    }
}
