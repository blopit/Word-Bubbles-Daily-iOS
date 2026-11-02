import Foundation

/// Every sound in the game, ported from the website's `Sound` object.
enum SoundEffect: Hashable, Sendable {
    case pick(index: Int, lift: Int)
    case unpick
    case lock(combo: Int)
    case bonus, earn, crack, wrong, near, hint, shuffle, win

    /// Pentatonic, so any run of picks sounds musical.
    static let scale = [392, 440, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66]

    private static func semitones(_ steps: Int) -> Double { pow(2, Double(steps) * 2 / 12) }

    /// The same sound with its parameters clamped, so one pre-rendered buffer serves everything that sounds alike.
    var canonical: SoundEffect {
        switch self {
        case let .pick(index, lift):
            return .pick(index: min(max(index, 0), Self.scale.count - 1), lift: min(max(lift, 0), 6))
        case let .lock(combo):
            return .lock(combo: min(max(combo, 1), 7))
        default:
            return self
        }
    }

    static let allCanonical: [SoundEffect] = {
        var all: [SoundEffect] = [.unpick, .bonus, .earn, .crack, .wrong, .near, .hint, .shuffle, .win]
        for combo in 1...7 { all.append(.lock(combo: combo)) }
        for index in scale.indices {
            for lift in 0...6 { all.append(.pick(index: index, lift: lift)) }
        }
        return all
    }()

    var tones: [Tone] {
        switch canonical {
        case let .pick(index, lift):
            let f = Self.scale[index] * Self.semitones(lift)
            return [
                Tone(freq: f * 0.6, duration: 0.14, volume: 0.22, glideTo: f * 1.25),
                Tone(freq: f * 2.5, delay: 0.01, duration: 0.05, volume: 0.03),
            ]
        case .unpick:
            return [Tone(freq: 500, duration: 0.13, volume: 0.15, glideTo: 280)]
        case let .lock(combo):
            let k = Self.semitones(combo - 1)
            let notes = [783.99, 987.77, 1174.66, 1567.98] + (combo >= 3 ? [1975.5] : [])
            return notes.enumerated().map { i, f in
                Tone(freq: f * k, delay: Double(i) * 0.055, duration: 0.32, wave: .triangle, volume: 0.1)
            }
        case .bonus:
            return [
                Tone(freq: 1046.5, duration: 0.22, volume: 0.1, glideTo: 1318.5),
                Tone(freq: 1567.98, delay: 0.08, duration: 0.3, volume: 0.08),
                Tone(freq: 2093, delay: 0.16, duration: 0.35, volume: 0.05),
            ]
        case .earn:
            return [1046.5, 1318.5, 1567.98, 2093].enumerated().map { i, f in
                Tone(freq: f, delay: Double(i) * 0.06, duration: 0.4, volume: 0.08)
            }
        case .crack:
            return [Tone(freq: 330, duration: 0.12, volume: 0.08, glideTo: 220)]
        case .wrong:
            return [Tone(freq: 196, duration: 0.2, volume: 0.2, glideTo: 120)]
        case .near:
            return [Tone(freq: 659.25, duration: 0.12, volume: 0.12), Tone(freq: 622.25, delay: 0.1, duration: 0.18, volume: 0.12)]
        case .hint:
            return [Tone(freq: 1318.5, duration: 0.45, volume: 0.09), Tone(freq: 1975.5, delay: 0.07, duration: 0.45, volume: 0.05)]
        case .shuffle:
            return [660, 880, 740, 990, 830].enumerated().map { i, f in
                Tone(freq: f, delay: Double(i) * 0.03, duration: 0.08, volume: 0.07, glideTo: f * 1.2)
            }
        case .win:
            return [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98].enumerated().map { i, f in
                Tone(freq: f, delay: Double(i) * 0.085, duration: 0.55, wave: .triangle, volume: 0.11)
            }
        }
    }
}
