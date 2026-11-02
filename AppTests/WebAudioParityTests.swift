import XCTest
@testable import WordBubbles

/// Reference numbers from the website's tone graph rendered in Chromium's OfflineAudioContext at 44.1kHz.
final class WebAudioParityTests: XCTestCase {
    private let reference: [(effect: SoundEffect, rms: Double, peak: Double)] = [
        (.pick(index: 0, lift: 0), 0.03591, 0.20464),
        (.unpick, 0.02503, 0.1428),
        (.lock(combo: 1), 0.02451, 0.12402),
        (.bonus, 0.01859, 0.09971),
        (.wrong, 0.03392, 0.18612),
        (.near, 0.02217, 0.11965),
        (.win, 0.03079, 0.14242),
    ]

    func testLoudnessMatchesWebAudio() {
        for item in reference {
            let samples = ToneSynth.render(item.effect.tones, sampleRate: 44_100).map(Double.init)
            let rms = (samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)).squareRoot()
            let peak = samples.map(abs).max()!
            XCTAssertEqual(rms, item.rms, accuracy: item.rms * 0.05, "\(item.effect) rms")
            XCTAssertEqual(peak, item.peak, accuracy: item.peak * 0.1, "\(item.effect) peak")
        }
    }
}

@MainActor
final class SoundEngineTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "wb-sound-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testDefaultsToOnAndPersistsTheToggle() {
        let store = defaults()
        XCTAssertTrue(SoundEngine(defaults: store).isOn)
        let engine = SoundEngine(defaults: store)
        engine.isOn = false
        XCTAssertFalse(SoundEngine(defaults: store).isOn)
    }

    func testPlaysEverythingWithoutTrouble() async throws {
        let engine = SoundEngine(defaults: defaults())
        engine.suspend()
        engine.resume()
        for effect in SoundEffect.allCanonical.prefix(20) { engine.play(effect) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(engine.isOn)
    }
}
