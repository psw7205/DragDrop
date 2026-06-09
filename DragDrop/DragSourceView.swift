import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    static let shelfItemID = NSPasteboard.PasteboardType("com.dragdrop.shelf-item")
    static let shelfItemIDs = NSPasteboard.PasteboardType("com.dragdrop.shelf-items")
}

final class ShelfDragPasteboardWriter: NSObject, NSPasteboardWriting {
    let fileURL: URL
    let shelfItemIDs: [UUID]

    init(fileURL: URL, shelfItemIDs: [UUID]) {
        self.fileURL = fileURL
        self.shelfItemIDs = shelfItemIDs
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        guard !shelfItemIDs.isEmpty else { return [.fileURL] }
        return [.fileURL, .shelfItemIDs, .shelfItemID]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            return fileURL.absoluteString
        case .shelfItemIDs:
            return shelfItemIDs.map(\.uuidString).joined(separator: "\n")
        case .shelfItemID:
            return shelfItemIDs.first?.uuidString
        default:
            return nil
        }
    }
}

struct DragSourceView: NSViewRepresentable {
    let urls: [URL]
    let icon: NSImage
    let itemIDs: [UUID]
    let onClick: (NSEvent.ModifierFlags) -> Void
    let contextMenu: () -> NSMenu

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.urls = urls
        view.icon = icon
        view.itemIDs = itemIDs
        view.onClick = onClick
        view.contextMenu = contextMenu
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.icon = icon
        nsView.itemIDs = itemIDs
        nsView.onClick = onClick
        nsView.contextMenu = contextMenu
    }
}

class DragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var icon = NSImage()
    var itemIDs: [UUID] = []
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var contextMenu: (() -> NSMenu)?

    private var dragOrigin: NSPoint?
    private var didDrag = false

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, !didDrag else { return }
        let current = event.locationInWindow
        guard hypot(current.x - origin.x, current.y - origin.y) > 4 else { return }

        didDrag = true
        dragOrigin = nil

        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let writer = ShelfDragPasteboardWriter(
                fileURL: url,
                shelfItemIDs: index == 0 ? itemIDs : []
            )
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(draggingFrame(for: index), contents: icon)
            return item
        }

        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    private func draggingFrame(for index: Int) -> NSRect {
        let offset = CGFloat(min(index, 4)) * 4
        return bounds.offsetBy(dx: offset, dy: -offset)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?(event.modifierFlags)
        }
        dragOrigin = nil
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu?(), !menu.items.isEmpty else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
