import AppKit

class GlobalDragMonitor {
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var monitors: [Any] = []
    private var isDragging = false
    private var lastChangeCount: Int

    init() {
        lastChangeCount = NSPasteboard(name: .drag).changeCount
    }

    func start() {
        guard monitors.isEmpty else { return }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.handleDragged()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDragged()
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp()
            return event
        } as Any)
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        isDragging = false
    }

    private func handleDragged() {
        let pb = NSPasteboard(name: .drag)
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let types = pb.types ?? []
        guard types.contains(.fileURL) else { return }

        if !isDragging {
            isDragging = true
            onDragStarted?()
        }
    }

    private func handleMouseUp() {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()
    }

    deinit {
        stop()
    }
}
