import UIKit

enum Haptic: Equatable, Sendable {
    case pick, lock, finish
}

@MainActor
protocol HapticPlaying: AnyObject {
    func play(_ haptic: Haptic)
}

/// Generators stay prepared so a pick lands with the touch.
@MainActor
final class SystemHaptics: HapticPlaying {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    init() {
        light.prepare()
        medium.prepare()
        notification.prepare()
    }

    func play(_ haptic: Haptic) {
        switch haptic {
        case .pick:
            light.impactOccurred()
            light.prepare()
        case .lock:
            medium.impactOccurred()
            medium.prepare()
            light.prepare()
        case .finish:
            notification.notificationOccurred(.success)
        }
    }
}
