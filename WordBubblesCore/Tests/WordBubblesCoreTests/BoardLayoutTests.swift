import CoreGraphics
import XCTest
@testable import WordBubblesCore

final class BoardLayoutTests: XCTestCase {
    private struct GoldenLayout: Decodable {
        let width: Double
        let height: Double
        let count: Int
        let fitHeight: Double
        let diameter: Double
        let fontSize: Double
        let points: [[Double]]
    }

    func testEveryGoldenLayout() throws {
        let layouts = try Golden.load([GoldenLayout].self, "layouts")
        XCTAssertEqual(layouts.count, 60)
        for golden in layouts {
            let label = "\(golden.width)x\(golden.height) n\(golden.count)"
            XCTAssertEqual(BoardLayout.fitHeight(width: golden.width, count: golden.count), golden.fitHeight, label)
            let layout = BoardLayout.compute(width: golden.width, height: golden.height, count: golden.count)
            XCTAssertEqual(layout.diameter, golden.diameter, label)
            XCTAssertEqual(layout.fontSize, golden.fontSize, label)
            XCTAssertEqual(layout.points.count, golden.points.count, label)
            for (point, expected) in zip(layout.points, golden.points) {
                XCTAssertEqual(point.x, expected[0], accuracy: 1e-9, label)
                XCTAssertEqual(point.y, expected[1], accuracy: 1e-9, label)
            }
        }
    }

    func testBoardsTheWebWouldNotLayOutAreEmptyRatherThanACrash() {
        for (width, height, count) in [(300.0, 300.0, 0), (39.0, 300.0, 5), (300.0, 39.0, 5)] {
            let layout = BoardLayout.compute(width: width, height: height, count: count)
            XCTAssertTrue(layout.points.isEmpty)
            XCTAssertEqual(layout.diameter, 0)
            XCTAssertEqual(layout.fontSize, 0)
        }
        XCTAssertEqual(BoardLayout.fitHeight(width: 300, count: 0), 0)
        XCTAssertEqual(BoardLayout.fitHeight(width: 39, count: 5), 0)
    }

    private let centers: [(id: String, center: CGPoint)] = [
        ("a", CGPoint(x: 0, y: 0)),
        ("b", CGPoint(x: 100, y: 0)),
        ("c", CGPoint(x: 112, y: 0)),
    ]

    func testHitsTheNearestBubble() {
        XCTAssertEqual(BoardLayout.hitTest(point: CGPoint(x: 5, y: 5), centers: centers, radius: 40), "a")
        XCTAssertEqual(BoardLayout.hitTest(point: CGPoint(x: 104, y: 0), centers: centers, radius: 40), "b")
        XCTAssertEqual(BoardLayout.hitTest(point: CGPoint(x: 108, y: 0), centers: centers, radius: 40), "c")
    }

    func testReachIsOnePointOneFiveRadii() {
        XCTAssertEqual(BoardLayout.hitTest(point: CGPoint(x: 45, y: 0), centers: centers, radius: 40), "a", "inside 46")
        XCTAssertNil(BoardLayout.hitTest(point: CGPoint(x: 47, y: 0), centers: centers, radius: 40), "outside 46")
    }

    func testTheEdgeOfTheReachCounts() {
        let edge = CGPoint(x: 40 * 1.15, y: 0)
        XCTAssertEqual(BoardLayout.hitTest(point: edge, centers: [("a", .zero)], radius: 40), "a")
    }

    func testConsumedBubblesAreSkipped() {
        XCTAssertEqual(BoardLayout.hitTest(point: CGPoint(x: 104, y: 0), centers: centers, radius: 40, consumed: ["b"]), "c")
    }

    func testTheNearestLiveBubbleMustBeInReach() {
        XCTAssertNil(BoardLayout.hitTest(point: CGPoint(x: 5, y: 0), centers: centers, radius: 40, consumed: ["a"]))
    }

    func testAnExactTieGoesToTheEarlierBubble() {
        XCTAssertEqual(BoardLayout.hitTest(point: CGPoint(x: 106, y: 0), centers: centers, radius: 40), "b")
    }

    func testNoBubbles() {
        XCTAssertNil(BoardLayout.hitTest(point: .zero, centers: [], radius: 40))
        XCTAssertNil(BoardLayout.hitTest(point: .zero, centers: centers, radius: 40, consumed: ["a", "b", "c"]))
    }
}
