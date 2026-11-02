import SwiftUI

/// The glossy bubble body, drawn once per size and scheme. Every bubble on the board then shares one image, so the
/// board costs a texture and a text layer per bubble rather than a gradient and three shadows.
@MainActor
enum BubbleSprite {
    /// Room for the drop shadow around the circle.
    static let margin: CGFloat = 34

    private struct Key: Hashable {
        let diameter: CGFloat
        let scheme: ColorScheme
        let scale: CGFloat
    }

    private static var cache: [Key: Image] = [:]

    static func image(diameter: CGFloat, scheme: ColorScheme, scale: CGFloat) -> Image {
        let key = Key(diameter: diameter, scheme: scheme, scale: scale)
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: BubbleBody(diameter: diameter, palette: Theme.palette(scheme)))
        renderer.scale = scale
        let image = renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "circle")
        if cache.count > 24 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

/// `.bub-body`: radial gloss, a hairline rim, two inner shadows and a soft drop shadow.
struct BubbleBody: View {
    let diameter: CGFloat
    let palette: Palette

    var body: some View {
        Circle()
            .fill(Theme.bubbleFill(diameter: diameter, palette: palette))
            .overlay {
                // inset 0 -8px 14px
                Circle()
                    .fill(.clear)
                    .overlay {
                        Circle()
                            .stroke(palette.bubbleInsetLow.color, lineWidth: 14)
                            .blur(radius: 7)
                            .offset(y: -8)
                            .clipShape(Circle())
                    }
                // inset 0 2px 3px
                Circle()
                    .stroke(palette.bubbleInsetHigh.color, lineWidth: 3)
                    .blur(radius: 1.5)
                    .offset(y: 2)
                    .clipShape(Circle())
            }
            .overlay { Circle().strokeBorder(palette.bubbleBorder.color, lineWidth: 1) }
            .frame(width: diameter, height: diameter)
            .background {
                // Shadow is cut out of the middle so see-through dark bubbles do not go muddy, as CSS box-shadow does.
                Circle()
                    .fill(palette.bubbleShadow.color)
                    .frame(width: diameter, height: diameter)
                    .blur(radius: 11)
                    .offset(y: 10)
                    .mask {
                        Rectangle()
                            .frame(width: diameter + BubbleSprite.margin * 2, height: diameter + BubbleSprite.margin * 2)
                            .overlay { Circle().frame(width: diameter, height: diameter).blendMode(.destinationOut) }
                            .compositingGroup()
                    }
            }
            .frame(width: diameter + BubbleSprite.margin * 2, height: diameter + BubbleSprite.margin * 2)
    }
}

/// A live version of the bubble for small decorative uses: the logo, tutorial balls, flights.
struct GlossyCircle: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    let diameter: CGFloat

    var body: some View {
        BubbleSprite.image(diameter: diameter, scheme: scheme, scale: displayScale)
            .frame(width: diameter + BubbleSprite.margin * 2, height: diameter + BubbleSprite.margin * 2)
            .frame(width: diameter, height: diameter)
    }
}
