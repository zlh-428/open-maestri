import XCTest
import CoreGraphics
@testable import open_maestri

// Story 2.3 AC：磁吸瓦片对齐测试
final class TileSnappingTests: XCTestCase {

    // MARK: - 基础吸附

    func testSnapToNearbyNodeEdge() {
        // 拖动节点的左边与目标节点右边接近时，应自动对齐
        let dragging = CGRect(x: 202, y: 100, width: 200, height: 150)  // x 比目标右边多 2
        let other = CGRect(x: 0, y: 100, width: 200, height: 150)       // 目标右边 x=200

        let (snapped, guidelines) = TileSnapping.snap(draggingFrame: dragging, against: [other])

        XCTAssertEqual(snapped.x, 200, accuracy: 0.5, "Should snap left edge to other's right edge")
        XCTAssertFalse(guidelines.isEmpty, "Should produce a guideline on snap")
    }

    func testNoXSnapWhenTooFar() {
        // X 方向距离 50 > 阈值 12，不应 X 方向吸附
        // Y 轴故意错开，避免 Y 方向意外吸附
        let dragging = CGRect(x: 250, y: 500, width: 200, height: 150)
        let other = CGRect(x: 0, y: 0, width: 200, height: 150)

        let (snapped, guidelines) = TileSnapping.snap(draggingFrame: dragging, against: [other])

        XCTAssertEqual(snapped.x, 250, accuracy: 0.5, "Should not snap X when too far")
        let xGuidelines = guidelines.filter { $0.axis == .vertical }
        XCTAssertTrue(xGuidelines.isEmpty, "Should not produce X guideline when too far")
    }

    func testSnapThresholdIs12() {
        XCTAssertEqual(TileSnapping.snapThreshold, 12.0,
                       "Snap threshold should be 12 canvas units")
    }

    func testSnapVerticalAlignment() {
        // 上边与目标下边接近
        let dragging = CGRect(x: 100, y: 308, width: 200, height: 150)  // y=308，目标下边 y=300
        let other = CGRect(x: 100, y: 100, width: 200, height: 200)     // 下边 y=300

        let (snapped, guidelines) = TileSnapping.snap(draggingFrame: dragging, against: [other])

        XCTAssertEqual(snapped.y, 300, accuracy: 0.5, "Should snap top to other's bottom")
        XCTAssertTrue(guidelines.contains { $0.axis == .horizontal },
                      "Should produce horizontal guideline")
    }

    func testSnapProducesVerticalGuideline() {
        let dragging = CGRect(x: 202, y: 50, width: 200, height: 150)
        let other = CGRect(x: 0, y: 0, width: 200, height: 150)

        let (_, guidelines) = TileSnapping.snap(draggingFrame: dragging, against: [other])

        XCTAssertTrue(guidelines.contains { $0.axis == .vertical },
                      "X-axis snap should produce vertical guideline")
    }

    func testSnapWithMultipleNodes() {
        let dragging = CGRect(x: 408, y: 100, width: 200, height: 150)
        let node1 = CGRect(x: 0, y: 100, width: 200, height: 150)
        let node2 = CGRect(x: 200, y: 100, width: 200, height: 150)  // 右边 x=400，距离 8

        let (snapped, _) = TileSnapping.snap(draggingFrame: dragging, against: [node1, node2])

        XCTAssertEqual(snapped.x, 400, accuracy: 0.5, "Should snap to closest edge")
    }

    // MARK: - GuideLine

    func testGuideLineAxisValues() {
        let hLine = GuideLine(axis: .horizontal, position: 100, start: 0, end: 200)
        let vLine = GuideLine(axis: .vertical, position: 50, start: 10, end: 150)
        XCTAssertEqual(hLine.axis, .horizontal)
        XCTAssertEqual(vLine.axis, .vertical)
        XCTAssertEqual(hLine.position, 100)
        XCTAssertEqual(vLine.start, 10)
    }
}
