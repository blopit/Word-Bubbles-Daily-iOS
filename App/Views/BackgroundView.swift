import SwiftUI

/// `.bg`: the three soft blobs on the page color.
struct BackgroundView: View {
    @Environment(\.colorScheme) private var scheme

    private struct Blob {
        let color: RGBA
        let radiusX, radiusY, centerX, centerY: Double
    }

    var body: some View {
        let palette = Theme.palette(scheme)
        let blobs = [
            Blob(color: palette.blob1, radiusX: 0.46, radiusY: 0.36, centerX: 0.10, centerY: 0.06),
            Blob(color: palette.blob2, radiusX: 0.42, radiusY: 0.34, centerX: 0.92, centerY: 0.18),
            Blob(color: palette.blob3, radiusX: 0.52, radiusY: 0.40, centerX: 0.50, centerY: 1.04),
        ]
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.bg.color))
            for blob in blobs {
                var layer = context
                layer.translateBy(x: blob.centerX * size.width, y: blob.centerY * size.height)
                layer.scaleBy(x: blob.radiusX * size.width, y: blob.radiusY * size.height)
                let clear = RGBA(Int(blob.color.r * 255), Int(blob.color.g * 255), Int(blob.color.b * 255), 0)
                let gradient = Gradient(stops: [
                    .init(color: blob.color.color, location: 0),
                    .init(color: clear.color, location: 0.7),
                ])
                layer.fill(
                    Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                    with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1)
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
