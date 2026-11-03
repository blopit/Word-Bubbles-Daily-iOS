import SwiftUI

/// Liquid Glass, for the few controls that float above the game. Bubbles, slots and results are content and never get
/// it. Before iOS 26 the same controls use a system material.
extension View {
    @ViewBuilder
    func floatingGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.85)) }
                    shape.strokeBorder(Theme.glassBorder, lineWidth: 1)
                }
            }
            .cssShadow(shape, color: Theme.glassShadow, blur: 24, y: 8)
        }
    }

    /// Lets this glass flow into, or out of, the other glass in its `GlassGroup` when one appears or disappears.
    @ViewBuilder
    func glassMorph(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// A bar pinned above scrolling content, which fades under it.
    @ViewBuilder
    func pinnedTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0) { bar().background(.bar) }
        }
    }
}

/// Glass that sits together, and blends as it moves. Sibling glass that isn't grouped can't sample itself.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
