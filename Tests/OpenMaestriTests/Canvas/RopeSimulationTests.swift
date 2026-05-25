import XCTest
import CoreGraphics
@testable import open_maestri

@MainActor
final class RopeSimulationTests: XCTestCase {
    let sim = RopeSimulation()

    func testControlPointCount() {
        let points = sim.compute(from: .zero, to: CGPoint(x: 100, y: 0))
        XCTAssertEqual(points.count, Constants.ropeControlPointCount)
        XCTAssertEqual(points.count, 21)
    }

    func testStartAndEndPoints() {
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 90, y: 80)
        let points = sim.compute(from: start, to: end)
        XCTAssertEqual(points.first?.x ?? 0, start.x, accuracy: 0.01)
        XCTAssertEqual(points.first?.y ?? 0, start.y, accuracy: 0.01)
        XCTAssertEqual(points.last?.x ?? 0, end.x, accuracy: 0.01)
        XCTAssertEqual(points.last?.y ?? 0, end.y, accuracy: 0.01)
    }

    func testMiddlePointHasSag() {
        // 水平绳子中点应该比直线高（y 更大，因为下垂）
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 200, y: 0)
        let points = sim.compute(from: start, to: end)
        let midPoint = points[points.count / 2]
        XCTAssertGreaterThan(midPoint.y, 0, "Rope should sag downward (y > 0)")
    }

    func testSerializeDeserializeRoundTrip() {
        let points = sim.compute(from: .zero, to: CGPoint(x: 100, y: 100))
        let serialized = sim.serialize(points)
        let restored = sim.deserialize(serialized)
        XCTAssertEqual(restored.count, points.count)
        for (orig, rest) in zip(points, restored) {
            XCTAssertEqual(orig.x, rest.x, accuracy: 0.001)
            XCTAssertEqual(orig.y, rest.y, accuracy: 0.001)
        }
    }

    func testBendRatioWithinBounds() {
        // 验证中点下垂量在合理范围内（非绳长，因为折线近似误差较大）
        let dist: CGFloat = 200
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: dist, y: 0)
        let points = sim.compute(from: start, to: end)
        let midPoint = points[points.count / 2]
        // 期望下垂量 > 0（有下垂），且不超过绳长的 20%
        XCTAssertGreaterThan(midPoint.y, 0)
        XCTAssertLessThan(midPoint.y, dist * 0.20)
    }
}
