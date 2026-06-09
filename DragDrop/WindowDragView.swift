import AppKit
import SwiftUI

struct WindowDragScreen: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect

    init(frame: NSRect, visibleFrame: NSRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

}

enum WindowDragGeometry {
    static func clampedOrigin(
        for frame: NSRect,
        mouseLocation: NSPoint,
        screens: [WindowDragScreen]
    ) -> NSPoint {
        guard let screen = targetScreen(for: frame, mouseLocation: mouseLocation, screens: screens) else {
            return frame.origin
        }

        return clamped(origin: frame.origin, size: frame.size, to: screen.visibleFrame)
    }

    private static func targetScreen(
        for frame: NSRect,
        mouseLocation: NSPoint,
        screens: [WindowDragScreen]
    ) -> WindowDragScreen? {
        if let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        let frameCenter = NSPoint(x: frame.midX, y: frame.midY)
        return screens.first(where: { $0.frame.contains(frameCenter) }) ?? screens.first
    }

    private static func clamped(origin: NSPoint, size: NSSize, to visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: clampedCoordinate(
                origin.x,
                min: visibleFrame.minX,
                max: visibleFrame.maxX - size.width,
                fallback: visibleFrame.midX - size.width / 2
            ),
            y: clampedCoordinate(
                origin.y,
                min: visibleFrame.minY,
                max: visibleFrame.maxY - size.height,
                fallback: visibleFrame.midY - size.height / 2
            )
        )
    }

    private static func clampedCoordinate(
        _ value: CGFloat,
        min minValue: CGFloat,
        max maxValue: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        guard minValue <= maxValue else { return fallback }
        return min(max(value, minValue), maxValue)
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

class WindowDragNSView: NSView {
    private var dragOrigin: NSPoint?

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window, let origin = dragOrigin else { return }
        let current = event.locationInWindow
        let dx = current.x - origin.x
        let dy = current.y - origin.y
        var frame = window.frame
        frame.origin.x += dx
        frame.origin.y += dy
        let screens = NSScreen.screens.map {
            WindowDragScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        frame.origin = WindowDragGeometry.clampedOrigin(
            for: frame,
            mouseLocation: NSEvent.mouseLocation,
            screens: screens
        )
        window.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
    }
}
