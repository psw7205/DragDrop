import AppKit

struct DragPasteboardSnapshot: Equatable {
    let changeCount: Int
    let types: Set<NSPasteboard.PasteboardType>

    init(changeCount: Int, types: [NSPasteboard.PasteboardType]) {
        self.changeCount = changeCount
        self.types = Set(types)
    }

    var hasSupportedDropPayload: Bool {
        !types.isDisjoint(with: [.fileURL, .URL, .legacyFilenames])
    }
}

extension NSPasteboard.PasteboardType {
    static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
}

class GlobalDragMonitor {
    var onDragStarted: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private let pasteboardSnapshotProvider: () -> DragPasteboardSnapshot
    private let mouseLocationProvider: () -> NSPoint
    private var monitors: [Any] = []
    private var isDragging = false
    private var lastChangeCount: Int

    init(pasteboardSnapshotProvider: @escaping () -> DragPasteboardSnapshot = {
        let pasteboard = NSPasteboard(name: .drag)
        return DragPasteboardSnapshot(changeCount: pasteboard.changeCount, types: pasteboard.types ?? [])
    }, mouseLocationProvider: @escaping () -> NSPoint = {
        NSEvent.mouseLocation
    }) {
        self.pasteboardSnapshotProvider = pasteboardSnapshotProvider
        self.mouseLocationProvider = mouseLocationProvider
        lastChangeCount = pasteboardSnapshotProvider().changeCount
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

        let pointerEndEvents: NSEvent.EventTypeMask = [.leftMouseUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: pointerEndEvents) { [weak self] _ in
            self?.handlePointerEnded()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: pointerEndEvents) { [weak self] event in
            self?.handlePointerEnded()
            return event
        } as Any)
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        isDragging = false
    }

    func handleDragged() {
        let snapshot = pasteboardSnapshotProvider()
        guard snapshot.changeCount != lastChangeCount else { return }
        lastChangeCount = snapshot.changeCount

        if snapshot.hasSupportedDropPayload {
            beginDragIfNeeded(at: mouseLocationProvider())
        } else {
            endDragIfNeeded()
        }
    }

    func handlePointerEnded() {
        endDragIfNeeded()
    }

    private func beginDragIfNeeded(at location: NSPoint) {
        guard !isDragging else { return }
        isDragging = true
        onDragStarted?(location)
    }

    private func endDragIfNeeded() {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()
    }

    deinit {
        stop()
    }
}
