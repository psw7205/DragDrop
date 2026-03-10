import AppKit

class GlobalDragMonitor {
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var isDragging = false
    private var isFileDrag = false
    private var checkTimer: Timer?
    private var lastChangeCount = 0

    init() {
        lastChangeCount = NSPasteboard(name: .drag).changeCount

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, !self.isDragging else { return }
            self.isDragging = true
            self.isFileDrag = false

            self.checkTimer?.invalidate()
            self.checkTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self, self.isDragging else { return }
                let pb = NSPasteboard(name: .drag)
                let currentCount = pb.changeCount
                guard currentCount != self.lastChangeCount else { return }
                self.lastChangeCount = currentCount
                if pb.types?.contains(.fileURL) == true {
                    self.isFileDrag = true
                    DispatchQueue.main.async { self.onDragStarted?() }
                }
            }
        }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard let self, self.isDragging else { return }
            self.checkTimer?.invalidate()
            self.isDragging = false
            if self.isFileDrag {
                self.isFileDrag = false
                DispatchQueue.main.async { self.onDragEnded?() }
            }
        }
    }

    deinit {
        checkTimer?.invalidate()
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
    }
}
