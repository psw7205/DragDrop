import AppKit
import SwiftUI

class ShelfHostingView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onLinkDropped: ((URL) -> Void)?
    var onItemReordered: ((UUID, Int) -> Void)?

    init<V: View>(rootView: V) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        registerForDraggedTypes([.fileURL, .URL, .shelfItemID])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragExited?()
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(.shelfItemID) == true {
            return .move
        }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // 내부 리오더 체크 (최우선)
        if let idString = pasteboard.string(forType: .shelfItemID),
           let sourceID = UUID(uuidString: idString) {
            let location = convert(sender.draggingLocation, from: nil)
            let targetIndex = gridIndex(from: location)
            onItemReordered?(sourceID, targetIndex)
            return true
        }

        // file URL
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !fileURLs.isEmpty {
            onFilesDropped?(fileURLs)
            return true
        }

        // non-file URL (웹 링크)
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: false]
        ) as? [URL], let webURL = urls.first,
           let scheme = webURL.scheme, ["http", "https"].contains(scheme.lowercased()) {
            onLinkDropped?(webURL)
            return true
        }

        return false
    }

    private func gridIndex(from point: NSPoint) -> Int {
        let headerHeight: CGFloat = ShelfLayout.headerHeight
        let padding: CGFloat = ShelfLayout.gridPadding
        let itemW: CGFloat = ShelfLayout.itemWidth
        let itemH: CGFloat = ShelfLayout.itemHeight
        let spacing: CGFloat = ShelfLayout.gridSpacing
        let columns = ShelfLayout.columns

        let viewHeight = bounds.height
        let y = viewHeight - point.y
        let contentY = y - headerHeight - padding
        let x = point.x - padding

        guard contentY >= 0, x >= 0 else { return 0 }

        let col = min(Int(x / (itemW + spacing)), columns - 1)
        let row = Int(contentY / (itemH + spacing))
        return row * columns + col
    }
}
