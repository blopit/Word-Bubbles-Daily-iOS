import SwiftUI
import UIKit
import WordBubblesCore

@main
struct WordBubblesApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: GameModel? = AppBootstrap.makeModel()

    var body: some Scene {
        WindowGroup {
            if let model {
                GameScreen()
                    .environment(model)
                    .preferredColorScheme(AppBootstrap.forcedScheme)
                    .onChange(of: scenePhase) { _, phase in
                        switch phase {
                        case .active: model.didBecomeActive()
                        case .background: model.didEnterBackground()
                        default: break
                        }
                    }
            }
        }
    }
}

/// Builds the one model. With `-uiTesting` it uses a throwaway store, no network and no sound.
@MainActor
enum AppBootstrap {
    static var isUnitTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// UI tests photograph both schemes; everyone else follows the system.
    static var forcedScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("-uiTestingDark") ? .dark : nil
    }

    static func makeModel() -> GameModel? {
        let arguments = ProcessInfo.processInfo.arguments
        let uiTesting = arguments.contains("-uiTesting")
        if isUnitTesting && !uiTesting { return nil }

        let today = Engine.dayNumber(for: Date())
        let store = ProgressStore(url: saveURL(uiTesting: uiTesting), today: today)
        if arguments.contains("-uiTestingSkipTutorial") { store.setTutorialDone() }

        let scheduler = MainScheduler()
        return GameModel(GameDependencies(
            store: store,
            records: uiTesting ? RecordsClient(transport: OfflineTransport()) : RecordsClient(),
            place: Place.detect(),
            sound: uiTesting ? SilentSound() : SoundEngine(),
            haptics: SystemHaptics(),
            scheduler: scheduler,
            measure: Theme.measureTile,
            reduceMotion: { UIAccessibility.isReduceMotionEnabled },
            usesNetwork: !uiTesting
        ))
    }

    private static func saveURL(uiTesting: Bool) -> URL {
        if uiTesting {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("wb-ui-\(UUID().uuidString)")
                .appendingPathComponent("progress.json")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("progress.json")
    }
}

/// Fails every request, so UI tests stay off the network.
struct OfflineTransport: RecordsTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        throw URLError(.notConnectedToInternet)
    }
}
