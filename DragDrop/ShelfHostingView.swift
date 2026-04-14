import AppKit
import SwiftUI

class ShelfHostingView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onLinkDropped: ((URL) -> Void)?

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
        registerForDraggedTypes([.fileURL, .URL])
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
        .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // file URL 먼저 시도
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
}
