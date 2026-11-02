import SwiftUI
import WordBubblesCore

/// The one screen: a fixed column, at most 520 wide, with the flight layer and overlay cards above it.
struct GameScreen: View {
    static let space = "game"
    @Environment(GameModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 680
            ZStack {
                BackgroundView()
                GameColumn()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 552)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FlightLayer()
                CelebrationLayer()
                OverlayHost()
            }
            .environment(\.compact, compact)
            .coordinateSpace(name: Self.space)
        }
        .foregroundStyle(Theme.fg)
        .font(Theme.body(15))
    }
}

/// Brand row, tabs, day switcher and the stage.
struct GameColumn: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            TopBar().modifier(Recedes(amount: 0.22, scales: true))
            if !model.isTutorial {
                LevelTabs().modifier(Recedes(amount: 0.22, scales: true))
                DayNav().modifier(Recedes(amount: 0.22, scales: true))
            }
            Group {
                if model.result != nil {
                    ResultStage()
                } else {
                    PlayStage()
                }
            }
            .modifier(SlideIn())
        }
    }
}

/// Chrome fades back while a word is being spelled, with no layout change.
struct Recedes: ViewModifier {
    @Environment(GameModel.self) private var model
    let amount: Double
    let scales: Bool

    func body(content: Content) -> some View {
        let spelling = model.trayActive
        content
            .opacity(spelling ? amount : 1)
            .scaleEffect(spelling && scales ? 0.94 : 1)
            .animation(.easeOut(duration: 0.35), value: spelling)
    }
}

/// `slideL` / `slideR`: the new day comes in from the side.
struct SlideIn: ViewModifier {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let direction = model.slideDirection == .left ? 24.0 : -24.0
        content.keyframeAnimator(initialValue: SlideValue(), trigger: reduceMotion ? 0 : model.slideCount) { view, value in
            view.offset(x: value.offset).opacity(value.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.offset) {
                MoveKeyframe(direction)
                CubicKeyframe(0, duration: 0.28)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.28)
            }
        }
    }

    private struct SlideValue {
        var offset = 0.0
        var opacity = 1.0
    }
}

/// Stacks the goal, tray, board and status. The board takes what it can up to its honeycomb height, and any height
/// left over mostly goes above, which keeps the board in the thumb zone on tall phones.
struct StageLayout: Layout {
    var spacing: CGFloat = 6
    var boardHeight: CGFloat
    var minBoardHeight: CGFloat = 110
    /// Share of the spare height placed above the content.
    var topShare: CGFloat = 0.72

    private func heights(_ subviews: Subviews, width: CGFloat, available: CGFloat) -> (sizes: [CGFloat], spare: CGFloat) {
        var sizes = subviews.map { view -> CGFloat in
            view[IsBoard.self] ? 0 : view.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let fixed = sizes.reduce(0, +) + gaps
        let room = max(available - fixed, minBoardHeight)
        let board = min(boardHeight, room)
        if let index = subviews.firstIndex(where: { $0[IsBoard.self] }) { sizes[index] = board }
        return (sizes, max(available - fixed - board, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 358, height: 600))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sizes, spare) = heights(subviews, width: bounds.width, available: bounds.height)
        var y = bounds.minY + spare * topShare
        for (view, height) in zip(subviews, sizes) {
            view.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
}

struct IsBoard: LayoutValueKey {
    static let defaultValue = false
}

/// `#play`.
struct PlayStage: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let fit = BoardLayout.fitHeight(width: proxy.size.width, count: model.orderCount)
            StageLayout(boardHeight: fit) {
                GoalView()
                TrayView()
                BoardView().layoutValue(key: IsBoard.self, value: true)
                if !model.isTutorial {
                    StatusRow()
                }
            }
        }
    }
}
