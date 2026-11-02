import XCTest
@testable import WordBubblesCore

/// Expected values come from running the JS mulberry32 in node; each is `rnd() * 2^32`.
final class Mulberry32Tests: XCTestCase {
    private func assertSequence(seed: Int, _ expected: [UInt32], line: UInt = #line) {
        var rng = Mulberry32(seed: seed)
        for (i, value) in expected.enumerated() {
            XCTAssertEqual(rng.next(), Double(value) / 4_294_967_296, "seed \(seed) draw \(i)", line: line)
        }
    }

    func testMatchesJS() {
        assertSequence(seed: 0, [1_144_304_738, 1_416_247, 958_946_056, 627_933_444])
        assertSequence(seed: 1, [2_693_262_067, 11_749_833, 2_265_367_787, 4_213_581_821])
        assertSequence(seed: 1_007_922, [909_597_202, 481_749_903, 1_902_092_041, 417_067_292])
    }

    func testNegativeAndHighBitSeeds() {
        assertSequence(seed: -1, [3_850_105_811, 813_802_916, 3_073_704_848, 4_054_706_436])
        assertSequence(seed: 2_147_483_648, [3_524_353_788, 1_924_613_307, 3_365_584_844, 2_199_219_949])
    }

    func testSeedsPast32BitsWrapLikeJSBitwiseOr() {
        assertSequence(seed: 4_294_967_295, [3_850_105_811, 813_802_916, 3_073_704_848, 4_054_706_436])
        assertSequence(seed: 4_294_967_301, [2_962_560_684, 3_318_907_087, 943_874_942, 2_676_532_661])
        assertSequence(seed: 4_294_982_344, [3_099_042_748, 2_711_037_565, 2_126_237_109, 2_867_129_628])
    }

    func testOutputStaysInUnitInterval() {
        var rng = Mulberry32(seed: 123)
        for _ in 0..<10_000 {
            let value = rng.next()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }
}
