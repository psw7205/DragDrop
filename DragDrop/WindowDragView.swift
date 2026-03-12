import AppKit
import SwiftUI

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
        guard let screen = window.screen ?? NSScreen.main else { return }
        let current = event.locationInWindow
        let dx = current.x - origin.x
        let dy = current.y - origin.y
        var frame = window.frame
        frame.origin.x += dx
        frame.origin.y += dy
        let visible = screen.visibleFrame
        let minX = visible.minX
        let maxX = visible.maxX - frame.width
        let minY = visible.minY
        let maxY = visible.maxY - frame.height
        frame.origin.x = min(max(frame.origin.x, minX), maxX)
        frame.origin.y = min(max(frame.origin.y, minY), maxY)
        window.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
    }
}
