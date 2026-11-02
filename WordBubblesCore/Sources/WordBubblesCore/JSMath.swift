import Foundation

/// JavaScript number semantics that differ from Swift's defaults.
enum JSMath {
    /// `Math.round`: ties go toward +infinity. `(x + 0.5).rounded(.down)` is wrong for values such as
    /// 0.49999999999999994, where the addition itself rounds up. `x - floor` is exact.
    static func round(_ value: Double) -> Double {
        let floor = value.rounded(.down)
        return value - floor >= 0.5 ? floor + 1 : floor
    }

    /// `value >>> 0`: truncate, then wrap modulo 2^32.
    static func toUInt32(_ value: Double) -> UInt32 {
        let modulus = 4_294_967_296.0
        let wrapped = fmod(value.rounded(.towardZero), modulus)
        return UInt32(wrapped < 0 ? wrapped + modulus : wrapped)
    }
}
