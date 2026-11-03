import SwiftUI
import UIKit
import WordBubblesCore

/// A color written as in the website's CSS.
struct RGBA: Sendable {
    let r, g, b, a: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
        a = 1
    }

    init(_ r: Int, _ g: Int, _ b: Int, _ a: Double) {
        self.r = Double(r) / 255
        self.g = Double(g) / 255
        self.b = Double(b) / 255
        self.a = a
    }

    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(ui) }
}

/// The site's `:root` tokens for one color scheme.
struct Palette: Sendable {
    let bg, blob1, blob2, blob3: RGBA
    let fg, muted: RGBA
    let glass, glassStrong, glassBorder, glassShadow: RGBA
    let bubbleHi, bubbleMid, bubbleLo, bubbleBorder: RGBA
    let bubbleShadow, bubbleInsetLow, bubbleInsetHigh: RGBA
    let accent, accent2, accentSoft, accentGlow, onAccent: RGBA
    let good, bad, badSoft, hint: RGBA
    let gold1, gold2, onGold: RGBA
    let secret1, secret2, onSecret, secretInk: RGBA
    let slotBorder, slotBg, dim, panel: RGBA

    static let light = Palette(
        bg: RGBA(0xedf3fb), blob1: RGBA(255, 170, 214, 0.55), blob2: RGBA(160, 208, 255, 0.65), blob3: RGBA(178, 255, 226, 0.55),
        fg: RGBA(0x172033), muted: RGBA(0x5d6c88),
        glass: RGBA(255, 255, 255, 0.52), glassStrong: RGBA(255, 255, 255, 0.74), glassBorder: RGBA(255, 255, 255, 0.85),
        glassShadow: RGBA(32, 48, 90, 0.12),
        bubbleHi: RGBA(255, 255, 255, 0.98), bubbleMid: RGBA(255, 255, 255, 0.72), bubbleLo: RGBA(190, 214, 255, 0.6),
        bubbleBorder: RGBA(255, 255, 255, 0.95),
        bubbleShadow: RGBA(30, 45, 90, 0.14), bubbleInsetLow: RGBA(110, 150, 220, 0.18), bubbleInsetHigh: RGBA(255, 255, 255, 0.95),
        accent: RGBA(0x0e86b3), accent2: RGBA(0x2c6fe3), accentSoft: RGBA(14, 134, 179, 0.16), accentGlow: RGBA(14, 134, 179, 0.35),
        onAccent: RGBA(0xffffff),
        good: RGBA(0x1f9e67), bad: RGBA(0xe04e52), badSoft: RGBA(224, 78, 82, 0.16), hint: RGBA(0xe5a11c),
        gold1: RGBA(0xf6c95a), gold2: RGBA(0xe3a21f), onGold: RGBA(0x2b1d00),
        secret1: RGBA(0xe4c6ff), secret2: RGBA(0x8a45d6), onSecret: RGBA(0x1b0b33), secretInk: RGBA(0x7a32c4),
        slotBorder: RGBA(23, 32, 51, 0.24), slotBg: RGBA(23, 32, 51, 0.06), dim: RGBA(10, 16, 30, 0.35), panel: RGBA(255, 255, 255, 0.92)
    )

    static let dark = Palette(
        bg: RGBA(0x0b1120), blob1: RGBA(214, 72, 160, 0.28), blob2: RGBA(46, 118, 230, 0.32), blob3: RGBA(32, 190, 150, 0.22),
        fg: RGBA(0xe6edf7), muted: RGBA(0x93a2bd),
        glass: RGBA(255, 255, 255, 0.07), glassStrong: RGBA(255, 255, 255, 0.11), glassBorder: RGBA(255, 255, 255, 0.16),
        glassShadow: RGBA(0, 0, 0, 0.35),
        bubbleHi: RGBA(255, 255, 255, 0.42), bubbleMid: RGBA(255, 255, 255, 0.12), bubbleLo: RGBA(120, 160, 255, 0.14),
        bubbleBorder: RGBA(255, 255, 255, 0.28),
        bubbleShadow: RGBA(0, 0, 0, 0.35), bubbleInsetLow: RGBA(60, 100, 200, 0.16), bubbleInsetHigh: RGBA(255, 255, 255, 0.35),
        accent: RGBA(0x38b6e0), accent2: RGBA(0x5b8cf2), accentSoft: RGBA(56, 182, 224, 0.2), accentGlow: RGBA(56, 182, 224, 0.4),
        onAccent: RGBA(0x06111f),
        good: RGBA(0x3ccf8c), bad: RGBA(0xff6b6e), badSoft: RGBA(255, 107, 110, 0.2), hint: RGBA(0xf3b73a),
        gold1: RGBA(0xf3c45a), gold2: RGBA(0xd99a1c), onGold: RGBA(0x241800),
        secret1: RGBA(0xe4c6ff), secret2: RGBA(0x8a45d6), onSecret: RGBA(0x1b0b33), secretInk: RGBA(0xe4c6ff),
        slotBorder: RGBA(230, 237, 247, 0.28), slotBg: RGBA(230, 237, 247, 0.07), dim: RGBA(0, 0, 0, 0.55), panel: RGBA(16, 24, 42, 0.94)
    )
}

/// Design tokens as adaptive colors, the fonts and the site's easing curves.
enum Theme {
    private static func token(_ path: KeyPath<Palette, RGBA>) -> Color {
        let light = Palette.light[keyPath: path].ui, dark = Palette.dark[keyPath: path].ui
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func palette(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }

    static let bg = token(\.bg)
    static let fg = token(\.fg)
    static let muted = token(\.muted)
    static let glass = token(\.glass)
    static let glassStrong = token(\.glassStrong)
    static let glassBorder = token(\.glassBorder)
    static let glassShadow = token(\.glassShadow)
    static let bubbleHi = token(\.bubbleHi)
    static let bubbleMid = token(\.bubbleMid)
    static let bubbleLo = token(\.bubbleLo)
    static let bubbleBorder = token(\.bubbleBorder)
    static let accent = token(\.accent)
    static let accent2 = token(\.accent2)
    static let accentSoft = token(\.accentSoft)
    static let accentGlow = token(\.accentGlow)
    static let onAccent = token(\.onAccent)
    static let good = token(\.good)
    static let bad = token(\.bad)
    static let badSoft = token(\.badSoft)
    static let hint = token(\.hint)
    static let gold1 = token(\.gold1)
    static let gold2 = token(\.gold2)
    static let onGold = token(\.onGold)
    static let secret1 = token(\.secret1)
    static let secret2 = token(\.secret2)
    static let onSecret = token(\.onSecret)
    static let secretInk = token(\.secretInk)
    static let slotBorder = token(\.slotBorder)
    static let slotBg = token(\.slotBg)
    static let dim = token(\.dim)
    static let panel = token(\.panel)

    // Fixed tints the CSS writes out in full, the same in both schemes.
    static let hintRing = RGBA(229, 161, 28, 0.35).color
    static let hintSoft = RGBA(229, 161, 28, 0.2).color
    static let hintHeatGlow = RGBA(229, 161, 28, 0.3).color
    static let hintHeatRing = RGBA(229, 161, 28, 0.22).color
    static let badHeatGlow = RGBA(224, 78, 82, 0.35).color
    static let goldGlow = RGBA(229, 161, 28, 0.35).color
    static let secretGlow = RGBA(138, 69, 214, 0.4).color
    static let badgeInk = RGBA(0x1b1b1b).color
    static let newRecord = RGBA(0x8a4ce6).color

    // MARK: Type

    static let displayWeight = Font.Weight.bold
    static let bodyWeight = Font.Weight.semibold

    /// Stands in for the website's Fredoka 600.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: displayWeight, design: .rounded)
    }

    /// Fixed sizes for the play screen, where the board's geometry decides what fits.
    static func body(_ size: CGFloat, weight: Font.Weight = bodyWeight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Sizes that follow Dynamic Type, for sheets and the score screen.
    static func text(_ style: Font.TextStyle, weight: Font.Weight = bodyWeight) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// The width of a tray tile's text, so tiles can be placed before they are drawn.
    static func measureTile(_ text: String) -> Double {
        let base = UIFont.systemFont(ofSize: 21, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 21) } ?? base
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: 21 * 0.02]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    // MARK: Motion

    /// cubic-bezier(0.2, 0.8, 0.2, 1)
    static func glide(_ duration: Double) -> Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: duration) }
    /// cubic-bezier(0.2, 0.9, 0.3, 1.15), used by the sliding tab thumb and moving bubbles
    static func settle(_ duration: Double) -> Animation { .timingCurve(0.2, 0.9, 0.3, 1.15, duration: duration) }
    /// cubic-bezier(0.2, 0.9, 0.3, 1.3), the `pop` easing
    static func popCurve(_ duration: Double) -> Animation { .timingCurve(0.2, 0.9, 0.3, 1.3, duration: duration) }

    static let metalGradient = LinearGradient(colors: [accent2, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentVertical = LinearGradient(colors: [accent2, accent], startPoint: .top, endPoint: .bottom)
    static let goldDiagonal = LinearGradient(colors: [gold1, gold2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldVertical = LinearGradient(colors: [gold1, gold2], startPoint: .top, endPoint: .bottom)
    static let secretDiagonal = LinearGradient(colors: [secret1, secret2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let secretVertical = LinearGradient(colors: [secret1, secret2], startPoint: .top, endPoint: .bottom)

    /// radial-gradient(circle at 32% 28%, hi, mid 48%, lo) on a box of this size
    static func bubbleFill(size: CGSize) -> RadialGradient {
        let cx = 0.32 * size.width, cy = 0.28 * size.height
        let corner = hypot(max(cx, size.width - cx), max(cy, size.height - cy))
        return RadialGradient(
            stops: [.init(color: bubbleHi, location: 0), .init(color: bubbleMid, location: 0.48), .init(color: bubbleLo, location: 1)],
            center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: corner
        )
    }

    /// The same, for shapes that must be computed in one color scheme, like the cached bubble sprite.
    static func bubbleFill(diameter: CGFloat, palette: Palette) -> RadialGradient {
        RadialGradient(
            stops: [
                .init(color: palette.bubbleHi.color, location: 0), .init(color: palette.bubbleMid.color, location: 0.48),
                .init(color: palette.bubbleLo.color, location: 1),
            ],
            center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: hypot(0.68, 0.72) * diameter
        )
    }
}

extension Level {
    var tint: Color {
        switch self {
        case .easy: return Theme.good
        case .medium: return Theme.hint
        case .hard: return Theme.bad
        case .tutorial: return Theme.muted
        }
    }

    /// A shape per level, so the level reads without its color.
    var symbol: String {
        switch self {
        case .easy: return "leaf.fill"
        case .medium: return "flame.fill"
        case .hard: return "mountain.2.fill"
        case .tutorial: return "graduationcap.fill"
        }
    }
}

extension FlashTone {
    var color: Color {
        switch self {
        case .good: return Theme.good
        case .hint: return Theme.hint
        case .bad: return Theme.bad
        case .secret: return Theme.secretInk
        }
    }
}

extension LockTone {
    var verticalFill: LinearGradient {
        switch self {
        case .accent: return Theme.accentVertical
        case .gold: return Theme.goldVertical
        case .secret: return Theme.secretVertical
        }
    }

    var diagonalFill: LinearGradient {
        switch self {
        case .accent: return Theme.metalGradient
        case .gold: return Theme.goldDiagonal
        case .secret: return Theme.secretDiagonal
        }
    }

    var ink: Color {
        switch self {
        case .accent: return Theme.onAccent
        case .gold: return Theme.onGold
        case .secret: return Theme.onSecret
        }
    }

    var glow: Color {
        switch self {
        case .accent: return Theme.accentGlow
        case .gold: return Theme.goldGlow
        case .secret: return Theme.secretGlow
        }
    }
}

/// Layout that scales with screen height, from the site's `max-height: 680px` query.
struct Compact: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compact: Bool {
        get { self[Compact.self] }
        set { self[Compact.self] = newValue }
    }
}

extension View {
    /// A `box-shadow`: drawn only outside the shape, so it does not darken a see-through panel.
    func cssShadow<S: Shape>(_ shape: S, color: Color, blur: CGFloat, y: CGFloat) -> some View {
        background {
            shape
                .fill(color)
                .blur(radius: blur / 2)
                .offset(y: y)
                .mask {
                    Rectangle()
                        .padding(-(blur * 2 + y))
                        .overlay { shape.blendMode(.destinationOut) }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
        }
    }
}

/// Shrinks on press like the site's `:active` rules.
struct PressScale: ButtonStyle {
    var amount = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? amount : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Keyframed `pop`: 0.4 → 1.08 → 1, fading in. Plays when `trigger` changes.
struct PopIn<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    var duration = 0.35
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: PopValue(), trigger: trigger) { view, value in
                view.scaleEffect(value.scale).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.4)
                    CubicKeyframe(1.08, duration: duration * 0.7)
                    CubicKeyframe(1, duration: duration * 0.3)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: duration * 0.7)
                }
            }
        }
    }

    private struct PopValue {
        var scale = 1.0
        var opacity = 1.0
    }
}
