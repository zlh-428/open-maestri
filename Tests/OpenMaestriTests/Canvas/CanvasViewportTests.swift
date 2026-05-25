import XCTest
import CoreGraphics
@testable import open_maestri

final class CanvasViewportTests: XCTestCase {

    // MARK: - 坐标转换（CanvasViewportView 核心逻辑）

    func testCanvasToScreenAtZoomOne() {
        let view = CanvasViewportView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.canvasOrigin = CGPoint(x: 9800, y: 8500)
        view.zoom = 1.0

        let canvasPoint = CGPoint(x: 9900, y: 8600)
        let screenPoint = view.canvasToScreen(canvasPoint)

        XCTAssertEqual(screenPoint.x, 100, accuracy: 0.01)
        XCTAssertEqual(screenPoint.y, 100, accuracy: 0.01)
    }

    func testScreenToCanvasRoundTrip() {
        let view = CanvasViewportView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.canvasOrigin = CGPoint(x: 9800, y: 8500)
        view.zoom = 1.5

        let original = CGPoint(x: 9850, y: 8550)
        let screen = view.canvasToScreen(original)
        let restored = view.screenToCanvas(screen)

        XCTAssertEqual(restored.x, original.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, original.y, accuracy: 0.001)
    }

    func testCanvasRectToScreenScalesCorrectly() {
        let view = CanvasViewportView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.canvasOrigin = .zero
        view.zoom = 2.0

        let canvasRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let screenRect = view.canvasRectToScreen(canvasRect)

        XCTAssertEqual(screenRect.width, 200, accuracy: 0.01)
        XCTAssertEqual(screenRect.height, 100, accuracy: 0.01)
        XCTAssertEqual(screenRect.origin.x, 20, accuracy: 0.01)
        XCTAssertEqual(screenRect.origin.y, 40, accuracy: 0.01)
    }

    func testZoomClampedRange() {
        // CanvasViewportView 的缩放范围 Constants.canvasMinZoom...canvasMaxZoom
        let minZoom = Constants.canvasMinZoom
        let maxZoom = Constants.canvasMaxZoom
        XCTAssertEqual(minZoom, 0.1)
        XCTAssertEqual(maxZoom, 3.0)
        XCTAssertLessThan(minZoom, maxZoom)
    }

    func testInitialOriginIsCanvasCenter() {
        let expectedOrigin = Constants.canvasInitialOrigin
        XCTAssertEqual(expectedOrigin.x, 9800, accuracy: 0.1)
        XCTAssertEqual(expectedOrigin.y, 8500, accuracy: 0.1)
    }

    // MARK: - Comparable.clamped 扩展

    func testClampedWithinRange() {
        let value: CGFloat = 1.0
        XCTAssertEqual(value.clamped(to: 0.25...2.0), 1.0)
    }

    func testClampedBelowMin() {
        let value: CGFloat = 0.1
        XCTAssertEqual(value.clamped(to: 0.25...2.0), 0.25)
    }

    func testClampedAboveMax() {
        let value: CGFloat = 5.0
        XCTAssertEqual(value.clamped(to: 0.25...2.0), 2.0)
    }
}
