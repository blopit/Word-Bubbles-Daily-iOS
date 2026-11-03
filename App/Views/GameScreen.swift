import SwiftUI
import WordBubblesCore

/// The one screen. The game is the surface: a column at most 520 wide, with the flight layer above it, and the few
/// controls floating on top get out of the way while a word is being spelled.
struct GameScreen: View {
    static let space = "game"
    @Environment(GameModel.self) private var model

    var body: some View {
        @Bindable var model = model
        GeometryReader { proxy in
            let compact = proxy.size.height < 680
            ZStack {
                BackgroundView()
                GameColumn(safeBottom: proxy.safeAreaInsets.bottom)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 552)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FlightLayer()
                CelebrationLayer()
            }
            .environment(\.compact, compact)
            .coordinateSpace(name: Self.space)
        }
        .foregroundStyle(Theme.fg)
        .font(Theme.body(15))
        .sheet(item: $model.overlay) { overlay in
            Group {
                switch overlay {
                case .help: HelpSheet()
                case .days: CalendarSheet()
                }
            }
            .environment(model)
        }
    }
}

/// The top row and the stage.
struct GameColumn: View {
    @Environment(GameModel.self) private var model
    let safeBottom: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            TopBar()
            Group {
                if model.result != nil {
                    ResultStage()
                } else {
                    PlayStage()
                }
            }
            .modifier(SlideIn())
        }
        .padding(.top, 4)
        .padding(.bottom, max(safeBottom, 10))
        .ignoresSafeArea(.container, edges: .bottom)
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

/// A sideways swipe moves between days. A shortcut for the calendar, so nothing depends on finding it.
struct DaySwipe: ViewModifier {
    @Environment(GameModel.self) private var model

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5, !model.trayActive, !model.isTutorial else { return }
                if dx > 0 { model.previousDay() } else { model.nextDay() }
            }
        )
    }
}

/// Stacks the goal, tray and board. The board and tray stay low in the thumb zone, and the goal sits in the middle of
/// whatever height is left. The board takes what it can up to its honeycomb height.
struct StageLayout: Layout {
    var spacing: CGFloat = 6
    var boardHeight: CGFloat
    var minBoardHeight: CGFloat = 110
    /// Share of the spare height placed above the goal. The rest goes below it.
    var topShare: CGFloat = 0.12

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
        for (index, (view, height)) in zip(subviews, sizes).enumerated() {
            view.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
            if index == 0 { y += spare * (1 - topShare) }
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
            }
        }
    }
}
