import Foundation
import AppKit

enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)
    case text(url: URL, snippet: String)
    case image(url: URL)
    case link(url: URL, originalURL: URL)
}

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let content: ShelfContent
    let addedAt: Date

    var displayName: String {
        switch content {
        case .file(_, let fileName): return fileName
        case .text(let url, _): return url.lastPathComponent
        case .image(let url): return url.lastPathComponent
        case .link(_, let originalURL): return originalURL.host ?? "link"
        }
    }

    var fileURL: URL {
        switch content {
        case .file(let url, _): return url
        case .text(let url, _): return url
        case .image(let url): return url
        case .link(let url, _): return url
        }
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    init(id: UUID = UUID(), content: ShelfContent, addedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.addedAt = addedAt
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }
}
