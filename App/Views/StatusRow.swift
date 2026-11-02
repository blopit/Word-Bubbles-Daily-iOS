import SwiftUI
import WordBubblesCore

/// `.status`: Shuffle, the meters and Hint, with the meters on the screen's center line.
struct StatusRow: View {
    @Environment(GameModel.self) private var model
    @Environment(\.compact) private var compact

    var body: some View {
        HStack(spacing: 6) {
            chip("Shuffle", id: "shuffle-button", action: model.shuffle) {
                Image(systemName: "shuffle").font(.system(size: 13, weight: .bold))
            }
            RankMeter()
                .frame(maxWidth: 190)
                .frame(maxWidth: .infinity)
            chip("Hint", id: "hint-button", action: model.useHint) { EmptyView() }
                .accessibilityHint("Using a hint removes the medal")
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 30)
        .modifier(Recedes(amount: 0.4, scales: false))
    }

    private func chip<Icon: View>(_ title: String, id: String, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon()
                Text(title).font(Theme.body(14))
            }
            .foregroundStyle(Theme.fg)
            .frame(width: 92, height: compact ? 40 : 44)
            .background(Theme.panel, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1) }
            .cssShadow(Capsule(), color: Theme.glassShadow, blur: 32, y: 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityIdentifier(id)
    }
}

/// `.rank`: points, clock, the three live stars and the medal timebar.
struct RankMeter: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(model.points)")
                    .font(Theme.display(16))
                    .accessibilityIdentifier("points")
                Text("pts").font(Theme.body(13)).foregroundStyle(Theme.muted)
                ClockLabel().padding(.leading, 4)
            }
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            LiveStars()
            TimeBar()
        }
        .padding(.horizontal, 11)
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
            MedalDot(key: model.clock?.medal?.key, size: 12)
            Text(model.clock?.timeText ?? "0:00")
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct LiveStars: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
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
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .frame(height: 20)
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

/// `.timebar`: drains toward the next medal down, and refills without animating when the medal changes.
struct TimeBar: View {
    @Environment(GameModel.self) private var model

    private func fill(_ key: String?) -> LinearGradient {
        let colors: [UInt32]
        switch key {
        case "gold": colors = [0xf6d36b, 0xe0a51a]
        case "silver": colors = [0xe3e8ef, 0xa3adbb]
        case "bronze": colors = [0xe8a974, 0xb8743d]
        default: colors = [0xc592ff, 0x7a3fe0]
        }
        return LinearGradient(colors: colors.map { RGBA($0).color }, startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        let clock = model.clock
        let key = clock?.medal?.key
        let fraction = min(max(clock?.fractionLeft ?? 0, 0), 1)
        ZStack(alignment: .leading) {
            Theme.slotBg
            if key != nil {
                fill(key)
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
                    .animation(.linear(duration: 0.5), value: fraction)
                    .id(key)
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.top, 4)
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
