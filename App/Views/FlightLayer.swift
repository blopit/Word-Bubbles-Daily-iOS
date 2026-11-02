import SwiftUI

/// Everything flying between the board, tray, slots and chips, above the column. Each flight animates itself, so
/// a frame of flight redraws only that flight.
struct FlightLayer: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.flights) { flight in
                FlightRunner(flight: flight)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FlightRunner: View {
    let flight: Flight
    @State private var progress = 0.0

    var body: some View {
        FlightView(flight: flight, progress: progress)
            .onAppear {
                withAnimation(Theme.glide(flight.duration)) { progress = 1 }
            }
    }
}

/// `.fly`: position, size and corners interpolate together, and the fill crossfades from bubble to tile.
private struct FlightView: View, Animatable {
    let flight: Flight
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }

    var body: some View {
        let width = mix(flight.from.width, flight.to.width)
        let height = mix(flight.from.height, flight.to.height)
        let center = CGPoint(x: mix(flight.from.midX, flight.to.midX), y: mix(flight.from.midY, flight.to.midY))
        Group {
            switch flight.kind {
            case .toTray:
                chunk(radius: mix(flight.from.height / 2, 11), tileAmount: progress, width: width, height: height)
            case .toBoard:
                chunk(radius: mix(11, flight.to.height / 2), tileAmount: 1 - progress, width: width, height: height)
            case let .word(tone):
                Text(flight.text)
                    .font(Theme.display(15))
                    .kerning(15 * 0.06)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(tone.ink)
                    .frame(width: width, height: height)
                    .background(tone.diagonalFill, in: Capsule())
                    .shadow(color: tone.glow, radius: 12, y: 10)
            }
        }
        .position(center)
    }

    private func chunk(radius: CGFloat, tileAmount: Double, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return Text(flight.text)
            .font(Theme.display(21))
            .kerning(21 * 0.02)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.fg)
            .frame(width: width, height: height)
            .background {
                ZStack {
                    shape.fill(Theme.accentSoft).opacity(tileAmount)
                    shape.fill(Theme.bubbleFill(size: CGSize(width: width, height: height))).opacity(1 - tileAmount)
                    shape.strokeBorder(Theme.bubbleBorder, lineWidth: 1).opacity(1 - tileAmount)
                }
            }
            .clipShape(shape)
    }
}

/// `.celebrate`: a few bubbles rise when a board is finished.
struct CelebrationLayer: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.celebration) { bubble in
                RisingBubble(bubble: bubble)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RisingBubble: View {
    let bubble: CelebrationBubble
    @State private var progress = 0.0

    var body: some View {
        RisingBubbleFrame(bubble: bubble, progress: progress)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: bubble.duration)) { progress = 1 }
            }
    }
}

private struct RisingBubbleFrame: View, Animatable {
    let bubble: CelebrationBubble
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let scale = 0.4 + 0.65 * progress
        let opacity = progress < 0.15 ? progress / 0.15 : 1 - (progress - 0.15) / 0.85
        GlossyCircle(diameter: bubble.size.rounded())
            .scaleEffect(scale)
            .opacity(opacity)
            .position(x: bubble.start.x + bubble.dx * progress, y: bubble.start.y + bubble.dy * progress)
    }
}
