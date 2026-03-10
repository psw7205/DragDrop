import Foundation
import AppKit

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let fileURL: URL
    let icon: NSImage
    let addedAt: Date

    init(id: UUID = UUID(), fileName: String, fileURL: URL) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        self.addedAt = Date()
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }
}
