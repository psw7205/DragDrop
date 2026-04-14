import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    static let shelfItemID = NSPasteboard.PasteboardType("com.dragdrop.shelf-item")
}

struct DragSourceView: NSViewRepresentable {
    let urls: [URL]
    let icon: NSImage
    let itemID: UUID
    let onClick: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.urls = urls
        view.icon = icon
        view.itemID = itemID
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.icon = icon
        nsView.itemID = itemID
        nsView.onClick = onClick
    }
}

class DragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var icon = NSImage()
    var itemID = UUID()
    var onClick: ((NSEvent.ModifierFlags) -> Void)?

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

        var items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(self.bounds, contents: self.icon)
            return item
        }

        let idItem = NSPasteboardItem()
        idItem.setString(itemID.uuidString, forType: .shelfItemID)
        let draggingItem = NSDraggingItem(pasteboardWriter: idItem)
        draggingItem.setDraggingFrame(self.bounds, contents: self.icon)
        items.append(draggingItem)

        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?(event.modifierFlags)
        }
        dragOrigin = nil
        didDrag = false
    }
}
