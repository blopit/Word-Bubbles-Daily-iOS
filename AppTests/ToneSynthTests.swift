import XCTest
@testable import WordBubbles

final class ToneSynthTests: XCTestCase {
    let rate = 44_100.0

    func testLengthIsLastToneEndPlusTheStopTail() {
        XCTAssertEqual(ToneSynth.length(of: [Tone(freq: 440, delay: 0.1, duration: 0.2)]), 0.33, accuracy: 1e-9)
        let tones = [Tone(freq: 440, delay: 0, duration: 0.5), Tone(freq: 880, delay: 0.1, duration: 0.1)]
        XCTAssertEqual(ToneSynth.length(of: tones), 0.53, accuracy: 1e-9)
        XCTAssertEqual(ToneSynth.render(tones, sampleRate: rate).count, Int((0.53 * rate).rounded(.up)))
    }

    func testGainFollowsTheWebAudioEnvelope() {
        let tone = Tone(freq: 440, duration: 0.2, volume: 0.1)
        XCTAssertEqual(ToneSynth.gain(tone, at: 0), 0.0001, accuracy: 1e-9)
        XCTAssertEqual(ToneSynth.gain(tone, at: 0.012), 0.1, accuracy: 1e-9)
        XCTAssertEqual(ToneSynth.gain(tone, at: 0.2), 0.0001, accuracy: 1e-9)
        // exponential: halfway through the attack is the geometric mean
        XCTAssertEqual(ToneSynth.gain(tone, at: 0.006), (0.0001 * 0.1).squareRoot(), accuracy: 1e-9)
        // halfway through the decay likewise
        XCTAssertEqual(ToneSynth.gain(tone, at: 0.106), (0.0001 * 0.1).squareRoot(), accuracy: 1e-9)
    }

    func testGlideIsExponentialOverEightyPercentThenHolds() {
        let tone = Tone(freq: 200, duration: 1, glideTo: 800)
        XCTAssertEqual(ToneSynth.frequency(tone, at: 0), 200, accuracy: 1e-9)
        XCTAssertEqual(ToneSynth.frequency(tone, at: 0.4), 400, accuracy: 1e-9)
        XCTAssertEqual(ToneSynth.frequency(tone, at: 0.8), 800, accuracy: 1e-9)
        XCTAssertEqual(ToneSynth.frequency(tone, at: 0.95), 800, accuracy: 1e-9)
        XCTAssertEqual(ToneSynth.frequency(Tone(freq: 300, duration: 1), at: 0.5), 300)
    }

    private func zeroCrossingHz(_ samples: ArraySlice<Float>) -> Double {
        var rising = 0
        var previous = samples.first ?? 0
        for s in samples.dropFirst() {
            if previous < 0 && s >= 0 { rising += 1 }
            previous = s
        }
        return Double(rising) / (Double(samples.count) / rate)
    }

    func testRenderedPitchMatchesForBothWaveforms() {
        for wave in [Waveform.sine, .triangle] {
            let samples = ToneSynth.render([Tone(freq: 440, duration: 0.5, wave: wave, volume: 0.2)], sampleRate: rate)
            XCTAssertEqual(zeroCrossingHz(samples[2_000..<16_000]), 440, accuracy: 5, "\(wave)")
        }
    }

    func testDelayIsSilentUntilTheToneStarts() {
        let samples = ToneSynth.render([Tone(freq: 440, delay: 0.1, duration: 0.1, volume: 0.2)], sampleRate: rate)
        XCTAssertTrue(samples[..<4_400].allSatisfy { $0 == 0 })
        XCTAssertGreaterThan(samples[4_400...].map(abs).max()!, 0.1)
    }

    func testPeakIsBoundedByVolumeAndNeverClips() {
        let peak = ToneSynth.render([Tone(freq: 523, duration: 0.3, wave: .triangle, volume: 0.11)], sampleRate: rate).map(abs).max()!
        XCTAssertLessThanOrEqual(peak, 0.11 + 1e-3)
        XCTAssertGreaterThan(peak, 0.09)
        for effect in SoundEffect.allCanonical {
            let peak = ToneSynth.render(effect.tones, sampleRate: rate).map(abs).max()!
            XCTAssertLessThanOrEqual(peak, 1, "\(effect)")
            XCTAssertGreaterThan(peak, 0.02, "\(effect)")
        }
    }

    func testTailsEndSilent() {
        for effect in SoundEffect.allCanonical {
            let samples = ToneSynth.render(effect.tones, sampleRate: rate)
            XCTAssertLessThan(samples.suffix(64).map(abs).max()!, 0.001, "\(effect) would click")
        }
    }
}

final class SoundEffectTests: XCTestCase {
    func testPickUsesTheScaleLiftAndTwoLayers() {
        let tones = SoundEffect.pick(index: 0, lift: 0).tones
        XCTAssertEqual(tones.count, 2)
        XCTAssertEqual(tones[0], Tone(freq: 392 * 0.6, duration: 0.14, volume: 0.22, glideTo: 392 * 1.25))
        XCTAssertEqual(tones[1], Tone(freq: 392 * 2.5, delay: 0.01, duration: 0.05, volume: 0.03))

        let lifted = SoundEffect.pick(index: 2, lift: 3).tones
        XCTAssertEqual(lifted[0].freq, 523.25 * pow(2, 6.0 / 12) * 0.6, accuracy: 1e-6)
    }

    func testPickClampsIndexAndLift() {
        XCTAssertEqual(SoundEffect.pick(index: 40, lift: 90).tones, SoundEffect.pick(index: 8, lift: 6).tones)
        XCTAssertEqual(SoundEffect.pick(index: 40, lift: 90).canonical, .pick(index: 8, lift: 6))
        XCTAssertEqual(SoundEffect.pick(index: -1, lift: -2).canonical, .pick(index: 0, lift: 0))
    }

    func testLockGrowsAFifthNoteFromComboThreeAndRisesWithCombo() {
        XCTAssertEqual(SoundEffect.lock(combo: 1).tones.map(\.freq), [783.99, 987.77, 1174.66, 1567.98])
        XCTAssertEqual(SoundEffect.lock(combo: 1).tones.map(\.delay), (0..<4).map { Double($0) * 0.055 }, "stagger")
        XCTAssertEqual(SoundEffect.lock(combo: 1).tones[0].wave, .triangle)
        XCTAssertEqual(SoundEffect.lock(combo: 1).tones[0].volume, 0.1)
        XCTAssertEqual(SoundEffect.lock(combo: 1).tones[0].duration, 0.32)
        XCTAssertEqual(SoundEffect.lock(combo: 2).tones[0].freq, 783.99 * pow(2, 2.0 / 12), accuracy: 1e-6)
        XCTAssertEqual(SoundEffect.lock(combo: 3).tones.count, 5)
        XCTAssertEqual(SoundEffect.lock(combo: 99).canonical, .lock(combo: 7))
        XCTAssertEqual(SoundEffect.lock(combo: 0).canonical, .lock(combo: 1))
    }

    func testTheRestPortVerbatim() {
        XCTAssertEqual(SoundEffect.unpick.tones, [Tone(freq: 500, duration: 0.13, volume: 0.15, glideTo: 280)])
        XCTAssertEqual(SoundEffect.crack.tones, [Tone(freq: 330, duration: 0.12, volume: 0.08, glideTo: 220)])
        XCTAssertEqual(SoundEffect.wrong.tones, [Tone(freq: 196, duration: 0.2, volume: 0.2, glideTo: 120)])
        XCTAssertEqual(SoundEffect.near.tones, [
            Tone(freq: 659.25, duration: 0.12, volume: 0.12), Tone(freq: 622.25, delay: 0.1, duration: 0.18, volume: 0.12),
        ])
        XCTAssertEqual(SoundEffect.hint.tones, [
            Tone(freq: 1318.5, duration: 0.45, volume: 0.09), Tone(freq: 1975.5, delay: 0.07, duration: 0.45, volume: 0.05),
        ])
        XCTAssertEqual(SoundEffect.bonus.tones, [
            Tone(freq: 1046.5, duration: 0.22, volume: 0.1, glideTo: 1318.5),
            Tone(freq: 1567.98, delay: 0.08, duration: 0.3, volume: 0.08),
            Tone(freq: 2093, delay: 0.16, duration: 0.35, volume: 0.05),
        ])
        XCTAssertEqual(SoundEffect.earn.tones.map(\.freq), [1046.5, 1318.5, 1567.98, 2093])
        XCTAssertEqual(SoundEffect.earn.tones.last?.delay ?? 0, 0.18, accuracy: 1e-9)
        XCTAssertEqual(SoundEffect.shuffle.tones.map(\.freq), [660, 880, 740, 990, 830])
        XCTAssertEqual(SoundEffect.shuffle.tones[1].glideTo ?? 0, 880 * 1.2, accuracy: 1e-9)
        XCTAssertEqual(SoundEffect.win.tones.map(\.freq), [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98])
        XCTAssertEqual(SoundEffect.win.tones[0].wave, .triangle)
        XCTAssertEqual(SoundEffect.win.tones[5].delay, 0.425, accuracy: 1e-9)
    }

    func testCatalogCoversEveryPitch() {
        XCTAssertEqual(Set(SoundEffect.allCanonical).count, 9 * 7 + 7 + 9)
    }
}
