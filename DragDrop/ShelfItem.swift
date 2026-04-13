import Foundation
import AppKit

enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)
    case text(string: String, savedURL: URL)
    case image(savedURL: URL, originalName: String?)
}

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let content: ShelfContent
    let addedAt: Date

    var displayName: String {
        switch content {
        case .file(_, let fileName): return fileName
        case .text(_, let savedURL): return savedURL.lastPathComponent
        case .image(_, let originalName): return originalName ?? "Image"
        }
    }

    var fileURL: URL {
        switch content {
        case .file(let url, _): return url
        case .text(_, let savedURL): return savedURL
        case .image(let savedURL, _): return savedURL
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
