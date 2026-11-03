import SwiftUI
import WordBubblesCore

/// A glass action on the score screen. One prominent button says what to do next, and the rest stay quiet.
struct GlassActionLabel: View {
    let title: String
    var systemImage: String?
    var prominent = false

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).lineLimit(1).minimumScaleFactor(0.75)
        }
        .font(Theme.text(prominent ? .body : .subheadline))
        .foregroundStyle(prominent ? Theme.onAccent : Theme.fg)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: prominent ? 52 : 44)
        .floatingGlass(in: Capsule(), tint: prominent ? Theme.accent : nil, interactive: true)
        .contentShape(Capsule())
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

/// `#result`: the score screen, in place of the board. Its content sits on the game's own background, with what to
/// do next floating below it, always in reach however long the content runs.
struct ResultStage: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                Group {
                    switch model.result {
                    case let .tutorial(result)?:
                        TutorialResultContent(result: result)
                    case let .board(result)?:
                        BoardResultContent(result: result, animated: model.resultAnimates)
                    case nil:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height - actionsHeight)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ResultActions(primary: primary, secondary: secondary)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
            }
            .modifier(DaySwipe())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result-stage")
    }

    @State private var actionsHeight: CGFloat = 0

    private var primary: ResultButton? {
        switch model.result {
        case let .tutorial(result)?: return result.primary
        case let .board(result)?: return result.primary
        case nil: return nil
        }
    }

    private var secondary: [ResultButton] {
        if case let .board(result)? = model.result { return result.secondary }
        return []
    }
}

private struct ResultActions: View {
    @Environment(GameModel.self) private var model
    let primary: ResultButton?
    let secondary: [ResultButton]

    var body: some View {
        GlassGroup {
            VStack(spacing: 8) {
                if let primary {
                    Button {
                        model.perform(primary.action)
                    } label: {
                        GlassActionLabel(title: primary.label, systemImage: primary.icon.symbol, prominent: true)
                    }
                    .buttonStyle(PressScale(amount: 0.96))
                    .accessibilityIdentifier("result-primary")
                }
                if !secondary.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(secondary.enumerated()), id: \.offset) { _, button in
                            secondaryButton(button)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func secondaryButton(_ button: ResultButton) -> some View {
        if button.action == .share {
            ShareLink(item: model.shareText) {
                GlassActionLabel(title: button.label, systemImage: button.icon.symbol)
            }
            .buttonStyle(PressScale(amount: 0.96))
            .accessibilityIdentifier("share-button")
        } else {
            Button {
                model.perform(button.action)
            } label: {
                GlassActionLabel(title: button.label, systemImage: button.icon.symbol)
            }
            .buttonStyle(PressScale(amount: 0.96))
            .accessibilityIdentifier("result-secondary")
        }
    }
}

struct TutorialResultContent: View {
    let result: TutorialResult

    var body: some View {
        VStack(spacing: 12) {
            Text(result.title)
                .font(Theme.text(.largeTitle, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(result.body)
                .font(Theme.text(.body))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
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

struct BoardResultContent: View {
    let result: BoardResult
    let animated: Bool

    var body: some View {
        VStack(spacing: 14) {
            BackToToday()
            VStack(spacing: 6) {
                Text(result.tag.uppercased())
                    .font(Theme.text(.caption))
                    .kerning(1.2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                BigStars(stars: result.stars, animated: animated)
            }
            bestLine
            pills
            Text(result.pointsLine)
                .font(Theme.text(.subheadline))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(result.words, id: \.self) { word in
                    chip(word, fill: Theme.metalGradient, ink: Theme.onAccent)
                }
            }
            if !result.bonusWords.isEmpty {
                VStack(spacing: 8) {
                    Text("Bonus words")
                        .font(Theme.text(.caption))
                        .foregroundStyle(Theme.muted)
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(result.bonusWords, id: \.word) { bonus in
                            chip(
                                bonus.word, fill: bonus.isSecret ? Theme.secretDiagonal : Theme.goldDiagonal,
                                ink: bonus.isSecret ? Theme.onSecret : Theme.onGold
                            )
                        }
                    }
                }
            }
            ForEach(Array(result.tips.enumerated()), id: \.offset) { _, tip in
                styled(tip, bold: Theme.hint, secret: Theme.secretInk, plain: Theme.fg)
                    .font(Theme.text(.subheadline))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.summary.isEmpty { summary }
            if result.showsCountdown { CountdownText() }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
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
                .font(Theme.text(.title3))
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
        .font(Theme.text(.subheadline))
        .monospacedDigit()
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                .font(Theme.text(.caption))
                .monospacedDigit()
        }
        .foregroundStyle(pill.isEmpty ? Theme.muted : pill.isHit || pill.icon != nil ? Theme.fg : Theme.muted)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
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
            .font(.system(size: 52, weight: .regular, design: .rounded))
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
