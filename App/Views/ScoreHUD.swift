import SwiftUI
import WordBubblesCore

/// Points, stars and the medal clock. Sits directly on the game with no glass: it is what you're playing for, not a
/// control.
struct ScoreHUD: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                Text("\(model.points)")
                    .font(Theme.display(20))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: model.points)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GameScreen.space)) } action: { frame in
                        model.scoreFrame = frame
                    }
                LiveStars()
            }
            ClockLabel()
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : model.scoreBump) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.15, duration: 0.2)
                CubicKeyframe(1, duration: 0.3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.scoreLabel + (model.clock.map { ", " + $0.accessibilityLabel } ?? ""))
        .accessibilityIdentifier("score")
    }
}

struct ClockLabel: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            MedalRing()
            Text(model.clock?.timeText ?? "0:00")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct LiveStars: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { index in
                LiveStar(on: index < model.stars)
            }
        }
    }
}

/// `starearn`: a star spins in when earned.
struct LiveStar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let on: Bool

    private struct Spin {
        var scale = 1.0
        var angle = 0.0
    }

    var body: some View {
        Text("★")
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .frame(height: 16)
            .foregroundStyle(on ? Theme.gold2 : Theme.slotBorder)
            .keyframeAnimator(initialValue: Spin(), trigger: reduceMotion ? false : on) { view, value in
                view.scaleEffect(value.scale).rotationEffect(.degrees(value.angle))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(on ? 0.3 : 1)
                    CubicKeyframe(on ? 1.6 : 1, duration: 0.36)
                    CubicKeyframe(1, duration: 0.24)
                }
                KeyframeTrack(\.angle) {
                    MoveKeyframe(on ? -40 : 0)
                    CubicKeyframe(on ? 10 : 0, duration: 0.36)
                    CubicKeyframe(0, duration: 0.24)
                }
            }
    }
}

/// The medal you'd get now, with a ring that drains toward the next medal down. Refills without animating when the
/// medal changes.
struct MedalRing: View {
    @Environment(GameModel.self) private var model
    private static let size: CGFloat = 16

    private func tint(_ key: String?) -> Color {
        switch key {
        case "gold": return RGBA(0xe0a51a).color
        case "silver": return RGBA(0xa3adbb).color
        case "bronze": return RGBA(0xb8743d).color
        default: return RGBA(0x7a3fe0).color
        }
    }

    var body: some View {
        let clock = model.clock
        let key = clock?.medal?.key
        let fraction = min(max(clock?.fractionLeft ?? 0, 0), 1)
        ZStack {
            Circle().stroke(Theme.slotBg, lineWidth: 2)
            if key != nil {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint(key), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: fraction)
                    .id(key)
            }
            MedalDot(key: key, size: Self.size - 7)
        }
        .frame(width: Self.size, height: Self.size)
    }
}

/// `.medal-dot`.
struct MedalDot: View {
    let key: String?
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                Circle().fill(.clear).shadow(color: .black.opacity(0.15), radius: 0, y: -2).clipShape(Circle())
            }
    }

    private var fill: AnyShapeStyle {
        let stops: [UInt32]
        switch key {
        case "gold": stops = [0xfff1b8, 0xe9b322, 0xb98510]
        case "silver": stops = [0xffffff, 0xc4ccd8, 0x8c96a6]
        case "bronze": stops = [0xffd9b8, 0xcd8a4f, 0x8f5527]
        case "record": stops = [0xf4e1ff, 0xa764f0, 0x6a2fb8]
        case "country", "local": stops = [0xd9f1ff, 0x3aa0e6, 0x1c5f9a]
        default: return AnyShapeStyle(Theme.slotBorder)
        }
        return AnyShapeStyle(RadialGradient(
            stops: [
                .init(color: RGBA(stops[0]).color, location: 0), .init(color: RGBA(stops[1]).color, location: 0.55),
                .init(color: RGBA(stops[2]).color, location: 1),
            ],
            center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.95
        ))
    }
}
