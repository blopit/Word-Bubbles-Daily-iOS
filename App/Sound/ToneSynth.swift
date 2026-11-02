import Foundation

enum Waveform: Equatable, Sendable {
    case sine, triangle
}

/// One oscillator note: the arguments of the web game's `tone()`.
struct Tone: Equatable, Sendable {
    var freq: Double
    var delay: Double = 0
    var duration: Double
    var wave: Waveform = .sine
    var volume: Double = 0.2
    var glideTo: Double?
}

/// Renders tones to samples with the same curves Web Audio uses for the website's sounds.
enum ToneSynth {
    private static let floor = 0.0001
    private static let attack = 0.012
    private static let stopTail = 0.03

    /// Seconds from the start of the first tone to the end of the last one.
    static func length(of tones: [Tone]) -> Double {
        tones.map { $0.delay + $0.duration + stopTail }.max() ?? 0
    }

    /// The envelope, `time` seconds into a tone. Exponential up to the volume in 12ms, then down to silence.
    static func gain(_ tone: Tone, at time: Double) -> Double {
        if time <= 0 { return floor }
        if time < attack { return floor * pow(tone.volume / floor, time / attack) }
        if time < tone.duration {
            return tone.volume * pow(floor / tone.volume, (time - attack) / (tone.duration - attack))
        }
        return floor
    }

    /// The pitch, `time` seconds into a tone. A glide is exponential and takes 80% of the tone.
    static func frequency(_ tone: Tone, at time: Double) -> Double {
        guard let target = tone.glideTo else { return tone.freq }
        let progress = min(max(time / (tone.duration * 0.8), 0), 1)
        return tone.freq * pow(target / tone.freq, progress)
    }

    private static func sample(_ wave: Waveform, phase: Double) -> Double {
        switch wave {
        case .sine:
            return sin(2 * .pi * phase)
        case .triangle:
            if phase < 0.25 { return 4 * phase }
            if phase < 0.75 { return 2 - 4 * phase }
            return 4 * phase - 4
        }
    }

    /// Mono samples of the tones mixed together, clamped to -1...1.
    static func render(_ tones: [Tone], sampleRate: Double) -> [Float] {
        let count = Int((length(of: tones) * sampleRate).rounded(.up))
        var mix = [Double](repeating: 0, count: count)
        for tone in tones {
            let first = Int((tone.delay * sampleRate).rounded(.up))
            let last = min(count, Int(((tone.delay + tone.duration + stopTail) * sampleRate).rounded(.up)))
            guard first < last else { continue }
            var phase = 0.0
            for index in first..<last {
                let time = Double(index) / sampleRate - tone.delay
                mix[index] += gain(tone, at: time) * sample(tone.wave, phase: phase)
                phase += frequency(tone, at: time) / sampleRate
                phase -= phase.rounded(.down)
            }
        }
        return mix.map { Float(min(max($0, -1), 1)) }
    }
}
