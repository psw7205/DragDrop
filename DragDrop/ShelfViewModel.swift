import Foundation
import AppKit
import Combine

enum ShelfDisplayState: Equatable {
    case hidden
    case indicator
    case expanded
}

class ShelfViewModel: ObservableObject {
    @Published var items: [ShelfItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var isExternalDragging = false
    @Published var isDragHovering = false

    var displayState: ShelfDisplayState {
        if !items.isEmpty { return .expanded }
        if isDragHovering { return .expanded }
        if isExternalDragging { return .indicator }
        return .hidden
    }

    var expandedHeight: CGFloat {
        let headerHeight: CGFloat = 30
        if items.isEmpty { return 160 }
        let rows = Int(ceil(Double(items.count) / 2.0))
        let gridHeight = CGFloat(rows) * 84 + CGFloat(max(0, rows - 1)) * 4 + 16
        return min(max(headerHeight + gridHeight, 160), 480)
    }

    // MARK: - Storage

    private let storageURL: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DragDrop/Items", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func addFiles(from urls: [URL]) {
        for url in urls where !isOwnFile(url) {
            let id = UUID()
            let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
            let destFile = destDir.appendingPathComponent(url.lastPathComponent)

            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: destFile)
                items.append(ShelfItem(id: id, fileName: url.lastPathComponent, fileURL: destFile))
            } catch {
                print("Failed to copy file: \(error)")
            }
        }
    }

    func removeItem(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        selectedIDs.remove(item.id)
        try? FileManager.default.removeItem(at: item.fileURL.deletingLastPathComponent())
    }

    func removeSelected() {
        let toRemove = items.filter { selectedIDs.contains($0.id) }
        toRemove.forEach { removeItem($0) }
    }

    private func isOwnFile(_ url: URL) -> Bool {
        url.path.contains(storageURL.path)
    }

    // MARK: - Selection

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectOnly(_ id: UUID) {
        selectedIDs = [id]
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    var selectedItems: [ShelfItem] {
        items.filter { selectedIDs.contains($0.id) }
    }
}
