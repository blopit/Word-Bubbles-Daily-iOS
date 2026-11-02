import SwiftUI
import WordBubblesCore

/// `.btn`.
struct ResultStyleButton: View {
    enum Style { case primary, secondary }
    let title: String
    var systemImage: String?
    let style: Style
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ButtonFace(title: title, systemImage: systemImage, style: style)
        }
        .buttonStyle(PressScale(amount: 0.96))
        .accessibilityIdentifier(id)
    }
}

struct ButtonFace: View {
    let title: String
    var systemImage: String?
    let style: ResultStyleButton.Style

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .bold)) }
            Text(title).font(Theme.body(15)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(style == .primary ? Theme.onAccent : Theme.fg)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background {
            if style == .primary {
                Capsule().fill(Theme.accentVertical).shadow(color: Theme.accentGlow, radius: 10, y: 8)
            } else {
                Capsule().fill(Theme.glass).overlay { Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1) }
            }
        }
        .contentShape(Capsule())
    }
}

/// `.btn.mini`.
struct MiniFace: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
            Text(title).font(Theme.body(12)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.fg)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.glass)
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.glassBorder, lineWidth: 1) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

extension ResultIcon {
    var symbol: String {
        switch self {
        case .next: return "arrow.right"
        case .earlier: return "calendar.badge.clock"
        case .share: return "square.and.arrow.up"
        case .play: return "play.fill"
        }
    }
}

/// `#result`: the card in place of the board, scrolling only if it has to.
struct ResultStage: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                Group {
                    switch model.result {
                    case let .tutorial(result)?:
                        TutorialResultCard(result: result)
                    case let .board(result)?:
                        BoardResultCard(result: result, animated: model.resultAnimates)
                    case nil:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
        }
        .accessibilityIdentifier("result-stage")
    }
}

struct TutorialResultCard: View {
    @Environment(GameModel.self) private var model
    let result: TutorialResult

    var body: some View {
        VStack(spacing: 12) {
            Text(result.title)
                .font(Theme.display(32))
                .kerning(-0.64)
                .accessibilityAddTraits(.isHeader)
            Text(result.body)
                .font(Theme.body(14, weight: .bold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
            ResultStyleButton(
                title: result.primary.label, systemImage: result.primary.icon.symbol, style: .primary, id: "result-primary"
            ) { model.perform(result.primary.action) }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .glassCard()
        .modifier(RiseIn())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result-card")
    }
}

/// `@keyframes rise`.
struct RiseIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    func body(content: Content) -> some View {
        content
            .opacity(risen || reduceMotion ? 1 : 0)
            .offset(y: risen || reduceMotion ? 0 : 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) { risen = true }
            }
    }
}

struct BoardResultCard: View {
    @Environment(GameModel.self) private var model
    let result: BoardResult
    let animated: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(result.tag.uppercased())
                .font(Theme.body(12))
                .kerning(1.2)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            BigStars(stars: result.stars, animated: animated)
            bestLine
            pills
            Text(result.pointsLine)
                .font(Theme.body(14, weight: .bold))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(result.words, id: \.self) { word in
                    chip(word, fill: Theme.metalGradient, ink: Theme.onAccent)
                }
            }
            if !result.bonusWords.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(result.bonusWords, id: \.word) { bonus in
                        chip(
                            bonus.word, fill: bonus.isSecret ? Theme.secretDiagonal : Theme.goldDiagonal,
                            ink: bonus.isSecret ? Theme.onSecret : Theme.onGold
                        )
                    }
                }
            }
            ForEach(Array(result.tips.enumerated()), id: \.offset) { _, tip in
                styled(tip, bold: Theme.hint, secret: Theme.secretInk, plain: Theme.fg)
                    .font(Theme.body(14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.summary.isEmpty { summary }
            if result.showsCountdown { CountdownText() }
            if let primary = result.primary {
                ResultStyleButton(title: primary.label, systemImage: primary.icon.symbol, style: .primary, id: "result-primary") {
                    model.perform(primary.action)
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(result.secondary.enumerated()), id: \.offset) { _, button in
                    secondary(button)
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .glassCard()
        .modifier(RiseIn())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result-card")
    }

    @ViewBuilder
    private var bestLine: some View {
        HStack(spacing: 8) {
            if let icon = result.best.icon {
                Text(icon).font(.system(size: 22))
            } else {
                MedalDot(key: result.best.key, size: 22)
            }
            Text(result.best.text)
                .font(Theme.body(16))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result-best")
    }

    private var pills: some View {
        FlowLayout {
            ForEach(result.pills, id: \.key) { pill in
                PillView(pill: pill)
            }
        }
    }

    private func chip(_ text: String, fill: LinearGradient, ink: Color) -> some View {
        Text(text)
            .font(Theme.display(15))
            .kerning(15 * 0.06)
            .foregroundStyle(ink)
            .frame(height: 30)
            .padding(.horizontal, 11)
            .background(fill, in: Capsule())
    }

    private var summary: some View {
        VStack(spacing: 6) {
            ForEach(result.summary, id: \.label) { row in
                HStack {
                    Text(row.label)
                    Spacer()
                    Text(row.value)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(Theme.body(14))
        .monospacedDigit()
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func secondary(_ button: ResultButton) -> some View {
        if button.action == .share {
            ShareLink(item: model.shareText) {
                MiniFace(title: button.label, systemImage: button.icon.symbol)
            }
            .buttonStyle(PressScale(amount: 0.96))
            .accessibilityIdentifier("share-button")
        } else {
            Button {
                model.perform(button.action)
            } label: {
                MiniFace(title: button.label, systemImage: button.icon.symbol)
            }
            .buttonStyle(PressScale(amount: 0.96))
            .accessibilityIdentifier("result-secondary")
        }
    }
}

/// `.medal-step`: one record or medal time.
struct PillView: View {
    let pill: ResultPill

    var body: some View {
        HStack(spacing: 6) {
            if let icon = pill.icon {
                Text(icon).font(.system(size: 13))
            } else {
                MedalDot(key: pill.key)
            }
            Text(pill.text)
                .font(Theme.body(12))
                .monospacedDigit()
        }
        .foregroundStyle(pill.isEmpty ? Theme.muted : pill.isHit || pill.icon != nil ? Theme.fg : Theme.muted)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.slotBg, in: Capsule())
        .overlay { if pill.isHit { Capsule().strokeBorder(Theme.fg, lineWidth: 2) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pill.accessibilityLabel)
    }
}

/// `.stars.big`: three stars, landing one by one the first time.
struct BigStars: View {
    let stars: Int
    let animated: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                BigStar(on: index < stars, delay: 0.35 + Double(index) * 0.15, animated: animated)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) of 3 stars")
        .accessibilityIdentifier("result-stars")
    }
}

/// `starland`.
struct BigStar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let on: Bool
    let delay: Double
    let animated: Bool
    @State private var trigger = false

    private struct Land {
        var scale = 1.0
        var angle = 0.0
        var opacity = 1.0
    }

    var body: some View {
        Text("★")
            .font(.system(size: 40, weight: .regular, design: .rounded))
            .foregroundStyle(on ? Theme.gold2 : Theme.slotBorder)
            .opacity(on && animated && !trigger && !reduceMotion ? 0 : 1)
            .keyframeAnimator(initialValue: Land(), trigger: trigger) { view, value in
                view.scaleEffect(value.scale).rotationEffect(.degrees(value.angle)).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(2.6)
                    CubicKeyframe(0.9, duration: 0.36)
                    CubicKeyframe(1, duration: 0.24)
                }
                KeyframeTrack(\.angle) {
                    MoveKeyframe(-25)
                    CubicKeyframe(4, duration: 0.36)
                    CubicKeyframe(0, duration: 0.24)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.36)
                }
            }
            .task {
                guard on, animated, !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(delay))
                trigger = true
            }
    }
}
