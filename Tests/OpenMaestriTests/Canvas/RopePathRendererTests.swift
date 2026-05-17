import XCTest
import CoreGraphics
@testable import open_maestri

// Story 5.1 AC：绳索路径渲染器测试
final class RopePathRendererTests: XCTestCase {

    // MARK: - 路径生成

    func testBezierPathFromPoints() {
        let points = (0..<21).map { i -> CGPoint in
            CGPoint(x: Double(i) * 10, y: Double(i) * 5)
        }
        let path = RopePathRenderer.bezierPath(from: points)
        XCTAssertFalse(path.isEmpty, "Should generate non-empty bezier path from 21 points")
    }

    func testBezierPathFromRawPoints() {
        let raw = (0..<21).map { i -> [Double] in [Double(i) * 10, 0] }
        let path = RopePathRenderer.bezierPath(from: raw)
        XCTAssertFalse(path.isEmpty)
    }

    func testEmptyPointsReturnsEmptyPath() {
        let path = RopePathRenderer.bezierPath(from: [CGPoint]())
        XCTAssertTrue(path.isEmpty)
    }

    func testSinglePointReturnsEmptyPath() {
        let path = RopePathRenderer.bezierPath(from: [CGPoint(x: 10, y: 20)])
        XCTAssertTrue(path.isEmpty, "Need at least 2 points")
    }

    // MARK: - 颜色状态编码（UX-DR5）

    func testIdleColorIsGray() {
        let color = RopePathRenderer.strokeColor(for: .idle)
        XCTAssertEqual(color, NSColor.systemGray.withAlphaComponent(0.7))
    }

    func testCommunicatingColorIsGreen() {
        let color = RopePathRenderer.strokeColor(for: .communicating)
        XCTAssertEqual(color, NSColor.systemGreen)
    }

    func testDisconnectedColorIsRed() {
        let color = RopePathRenderer.strokeColor(for: .disconnected)
        XCTAssertEqual(color, NSColor.systemRed)
    }

    func testErrorColorIsOrange() {
        let color = RopePathRenderer.strokeColor(for: .error)
        XCTAssertEqual(color, NSColor.systemOrange)
    }

    // MARK: - 线宽和虚线

    func testCommunicatingLineIsThicker() {
        let comm = RopePathRenderer.lineWidth(for: .communicating)
        let idle = RopePathRenderer.lineWidth(for: .idle)
        XCTAssertGreaterThan(comm, idle, "Communicating line should be thicker")
    }

    func testIdleIsDashed() {
        XCTAssertTrue(RopePathRenderer.isDashed(for: .idle))
        XCTAssertTrue(RopePathRenderer.isDashed(for: .disconnected))
    }

    func testCommunicatingIsNotDashed() {
        XCTAssertFalse(RopePathRenderer.isDashed(for: .communicating))
    }

    // MARK: - 中点

    func testMidpointOfPoints() {
        let points = (0..<21).map { i -> CGPoint in CGPoint(x: Double(i) * 10, y: 0) }
        let mid = RopePathRenderer.midpoint(of: points)
        XCTAssertNotNil(mid)
        XCTAssertEqual(mid?.x ?? 0, 100, accuracy: 0.01) // 21점 중 10번째 = x=100
    }

    func testMidpointOfEmptyIsNil() {
        XCTAssertNil(RopePathRenderer.midpoint(of: []))
    }
}
