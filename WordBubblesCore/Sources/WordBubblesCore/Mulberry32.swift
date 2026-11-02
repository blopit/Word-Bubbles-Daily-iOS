/// A source of doubles in [0, 1), standing in for the web engine's `rnd()` closures.
public protocol RandomSource {
    mutating func next() -> Double
}

/// The seeded generator behind every board. It must stay bit-exact with the web version.
public struct Mulberry32: RandomSource, Sendable {
    private var state: UInt32

    /// Seeds past 32 bits wrap, matching JS `a |= 0`.
    public init(seed: Int) {
        state = UInt32(truncatingIfNeeded: seed)
    }

    public mutating func next() -> Double {
        state &+= 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}
