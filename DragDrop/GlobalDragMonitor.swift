import AppKit

class GlobalDragMonitor {
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var globalDragMonitor: Any?
    private var globalUpMonitor: Any?
    private var localDragMonitor: Any?
    private var localUpMonitor: Any?
    private var isDragging = false
    private var isFileDrag = false
    private var checkTimer: Timer?
    private var endCheckTimer: Timer?
    private var lastChangeCount = 0

    init() {
        lastChangeCount = NSPasteboard(name: .drag).changeCount

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.handleDragEvent()
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDragEvent()
            return event
        }

        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleDragEnded()
        }
        localUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleDragEnded()
            return event
        }
    }

    private func handleDragEvent() {
        if !isDragging {
            isDragging = true
            isFileDrag = false
            startCheckingPasteboard()
        }

        if !isFileDrag {
            evaluateDragPasteboard()
        }
    }

    private func startCheckingPasteboard() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, self.isDragging, !self.isFileDrag else {
                self?.checkTimer?.invalidate()
                return
            }
            self.evaluateDragPasteboard()
        }
    }

    private func evaluateDragPasteboard() {
        let pb = NSPasteboard(name: .drag)
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let types = pb.types ?? []
        let hasFileURL = types.contains(.fileURL)
            || (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.isEmpty == false)
        guard hasFileURL else { return }

        isFileDrag = true
        checkTimer?.invalidate()
        startCheckingDragEnd()
        DispatchQueue.main.async { [weak self] in
            self?.onDragStarted?()
        }
    }

    private func startCheckingDragEnd() {
        endCheckTimer?.invalidate()
        endCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isDragging else {
                self.endCheckTimer?.invalidate()
                return
            }

            let pb = NSPasteboard(name: .drag)
            let types = pb.types ?? []
            let hasFileURL = types.contains(.fileURL)
                || (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.isEmpty == false)
            if !hasFileURL {
                self.handleDragEnded()
            }
        }
    }

    private func handleDragEnded() {
        guard isDragging else { return }

        checkTimer?.invalidate()
        endCheckTimer?.invalidate()
        isDragging = false

        guard isFileDrag else { return }
        isFileDrag = false
        DispatchQueue.main.async { [weak self] in
            self?.onDragEnded?()
        }
    }

    deinit {
        checkTimer?.invalidate()
        endCheckTimer?.invalidate()
        if let globalDragMonitor { NSEvent.removeMonitor(globalDragMonitor) }
        if let globalUpMonitor { NSEvent.removeMonitor(globalUpMonitor) }
        if let localDragMonitor { NSEvent.removeMonitor(localDragMonitor) }
        if let localUpMonitor { NSEvent.removeMonitor(localUpMonitor) }
    }
}
