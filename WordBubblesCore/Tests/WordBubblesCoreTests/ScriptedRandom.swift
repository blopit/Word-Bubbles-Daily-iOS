@testable import WordBubblesCore

/// Plays back fixed draws, repeating the last, so a test can force each branch of the engine.
struct ScriptedRandom: RandomSource {
    private let values: [Double]
    private(set) var draws = 0

    init(_ values: Double...) {
        self.values = values
    }

    mutating func next() -> Double {
        defer { draws += 1 }
        return values[min(draws, values.count - 1)]
    }
}
