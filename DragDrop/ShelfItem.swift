import Foundation
import AppKit

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let fileURL: URL
    let addedAt: Date

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    init(id: UUID = UUID(), fileName: String, fileURL: URL, addedAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.addedAt = addedAt
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }
}
