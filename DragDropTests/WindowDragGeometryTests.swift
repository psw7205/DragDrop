import XCTest
@testable import DragDrop

final class WindowDragGeometryTests: XCTestCase {
    func testClampKeepsOriginWithinScreenUnderMouse() {
        let screen = WindowDragScreen(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: NSRect(x: 0, y: 0, width: 100, height: 100)
        )
        let proposed = NSRect(x: -10, y: 90, width: 40, height: 40)

        let origin = WindowDragGeometry.clampedOrigin(
            for: proposed,
            mouseLocation: NSPoint(x: 50, y: 50),
            screens: [screen]
        )

        XCTAssertEqual(origin, NSPoint(x: 0, y: 60))
    }

    func testUsesScreenUnderMouseForMultiMonitorDrag() {
        let primary = WindowDragScreen(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: NSRect(x: 0, y: 0, width: 100, height: 100)
        )
        let secondary = WindowDragScreen(
            frame: NSRect(x: 100, y: 0, width: 100, height: 100),
            visibleFrame: NSRect(x: 100, y: 0, width: 100, height: 100)
        )
        let proposed = NSRect(x: 115, y: 20, width: 40, height: 40)

        let origin = WindowDragGeometry.clampedOrigin(
            for: proposed,
            mouseLocation: NSPoint(x: 150, y: 50),
            screens: [primary, secondary]
        )

        XCTAssertEqual(origin, NSPoint(x: 115, y: 20))
    }

    func testFallsBackToFrameCenterWhenMouseIsOutsideKnownScreens() {
        let primary = WindowDragScreen(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: NSRect(x: 0, y: 0, width: 100, height: 100)
        )
        let secondary = WindowDragScreen(
            frame: NSRect(x: 100, y: 0, width: 100, height: 100),
            visibleFrame: NSRect(x: 100, y: 0, width: 100, height: 100)
        )
        let proposed = NSRect(x: 170, y: 70, width: 40, height: 40)

        let origin = WindowDragGeometry.clampedOrigin(
            for: proposed,
            mouseLocation: NSPoint(x: -500, y: -500),
            screens: [primary, secondary]
        )

        XCTAssertEqual(origin, NSPoint(x: 160, y: 60))
    }

    func testCentersWhenFrameIsLargerThanVisibleScreen() {
        let screen = WindowDragScreen(
            frame: NSRect(x: 0, y: 0, width: 30, height: 30),
            visibleFrame: NSRect(x: 0, y: 0, width: 30, height: 30)
        )
        let proposed = NSRect(x: 0, y: 0, width: 50, height: 50)

        let origin = WindowDragGeometry.clampedOrigin(
            for: proposed,
            mouseLocation: NSPoint(x: 10, y: 10),
            screens: [screen]
        )

        XCTAssertEqual(origin, NSPoint(x: -10, y: -10))
    }
}
