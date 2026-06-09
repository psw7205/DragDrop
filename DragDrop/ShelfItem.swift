import Foundation
import AppKit
import UniformTypeIdentifiers

enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)
    case text(url: URL, snippet: String)
    case image(url: URL)
    case link(url: URL, originalURL: URL)
}

enum ShelfSortMode: String, CaseIterable, Identifiable {
    case manual
    case added
    case name
    case kind
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .added: return "Added"
        case .name: return "Name"
        case .kind: return "Kind"
        case .size: return "Size"
        }
    }
}

struct ShelfItemMetadata: Equatable {
    let kind: String
    let sizeBytes: Int64
    let addedAt: Date
    let searchText: String
    let detailText: String
    let tooltipText: String

    static func make(for item: ShelfItem) -> ShelfItemMetadata {
        let kind = kindTitle(for: item)
        let sizeBytes = fileSize(for: item.fileURL)
        let sizeText = byteFormatter.string(fromByteCount: sizeBytes)
        let addedText = dateFormatter.string(from: item.addedAt)
        let host = linkHost(for: item)

        var searchParts = [
            item.displayName,
            item.fileURL.lastPathComponent,
            item.fileURL.pathExtension,
            kind,
        ]

        if case .text(_, let snippet) = item.content {
            searchParts.append(snippet)
        }
        if case .link(_, let originalURL) = item.content {
            searchParts.append(originalURL.absoluteString)
            if let host {
                searchParts.append(host)
            }
        }

        let detailText = host.map { "\($0) - \(sizeText)" } ?? "\(kind) - \(sizeText)"
        let tooltipText = [
            item.displayName,
            kind,
            sizeText,
            "Added \(addedText)",
            host,
        ].compactMap { $0 }.joined(separator: "\n")

        return ShelfItemMetadata(
            kind: kind,
            sizeBytes: sizeBytes,
            addedAt: item.addedAt,
            searchText: searchParts.joined(separator: " "),
            detailText: detailText,
            tooltipText: tooltipText
        )
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func fileSize(for url: URL) -> Int64 {
        ShelfStorage.totalBytes(for: url)
    }

    private static func linkHost(for item: ShelfItem) -> String? {
        guard case .link(_, let originalURL) = item.content else { return nil }
        return originalURL.host
    }

    private static func kindTitle(for item: ShelfItem) -> String {
        switch item.content {
        case .link:
            return "Link"
        case .image:
            return "Image"
        case .text:
            return "Text"
        case .file:
            let ext = item.fileURL.pathExtension
            guard !ext.isEmpty,
                  let type = UTType(filenameExtension: ext),
                  let description = type.localizedDescription,
                  !description.isEmpty else {
                return "File"
            }
            return description
        }
    }
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
