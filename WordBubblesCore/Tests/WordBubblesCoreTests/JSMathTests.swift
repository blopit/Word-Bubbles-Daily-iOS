import XCTest
@testable import WordBubblesCore

/// Expected values come from node.
final class JSMathTests: XCTestCase {
    func testRoundTiesGoTowardPositiveInfinity() {
        XCTAssertEqual(JSMath.round(0.5), 1)
        XCTAssertEqual(JSMath.round(2.5), 3)
        XCTAssertEqual(JSMath.round(-0.5), 0)
        XCTAssertEqual(JSMath.round(-2.5), -2)
    }

    func testRoundHandlesValuesWhereAddingHalfLosesPrecision() {
        XCTAssertEqual(JSMath.round(0.49999999999999994), 0)
        XCTAssertEqual(JSMath.round(1.4999999999999998), 1)
        XCTAssertEqual(JSMath.round(4_503_599_627_370_497), 4_503_599_627_370_497)
    }

    func testRoundOrdinaryValues() {
        XCTAssertEqual(JSMath.round(-0.2), 0)
        XCTAssertEqual(JSMath.round(-4.6), -5)
        XCTAssertEqual(JSMath.round(4.4), 4)
    }

    func testUInt32ConversionMatchesUnsignedShift() {
        XCTAssertEqual(JSMath.toUInt32(0), 0)
        XCTAssertEqual(JSMath.toUInt32(4_294_967_296), 0)
        XCTAssertEqual(JSMath.toUInt32(4_294_967_301), 5)
        XCTAssertEqual(JSMath.toUInt32(-1), 4_294_967_295)
        XCTAssertEqual(JSMath.toUInt32(-4_294_967_297), 4_294_967_295)
        XCTAssertEqual(JSMath.toUInt32(3.9), 3)
        XCTAssertEqual(JSMath.toUInt32(-3.9), 4_294_967_293)
    }
}
