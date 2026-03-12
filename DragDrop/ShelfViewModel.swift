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
    @Published var lastErrorMessage: String?
    @Published var showDeleteAllConfirmation = false
    @Published private(set) var pendingAddCount = 0

    var displayState: ShelfDisplayState {
        if !items.isEmpty { return .expanded }
        if pendingAddCount > 0 { return .expanded }
        if isDragHovering { return .expanded }
        if lastErrorMessage != nil { return .expanded }
        if showDeleteAllConfirmation { return .expanded }
        if isExternalDragging { return .indicator }
        return .hidden
    }

    var expandedHeight: CGFloat {
        if items.isEmpty { return ShelfLayout.minHeight }
        let rows = Int(ceil(Double(items.count) / Double(ShelfLayout.columns)))
        let gridHeight = CGFloat(rows) * ShelfLayout.itemHeight
            + CGFloat(max(0, rows - 1)) * ShelfLayout.gridSpacing
            + ShelfLayout.gridPadding * 2
        return min(max(ShelfLayout.headerHeight + gridHeight, ShelfLayout.minHeight), ShelfLayout.maxHeight)
    }

    // MARK: - Storage

    private let storageURL: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DragDrop/Items", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            NSLog("DragDrop: Failed to create storage directory: %@", error.localizedDescription)
        }
        return url
    }()

    init() {
        loadPersistedItems()
    }

    func addFilesAsync(from urls: [URL]) {
        let candidates = urls.filter { !isOwnFile($0) }
        guard !candidates.isEmpty else { return }

        pendingAddCount += 1
        let storageURL = self.storageURL
        DispatchQueue.global(qos: .userInitiated).async {
            var copied: [(id: UUID, fileName: String, fileURL: URL)] = []
            var failures = 0

            for url in candidates {
                let id = UUID()
                let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
                let destFile = destDir.appendingPathComponent(url.lastPathComponent)

                do {
                    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destFile)
                    copied.append((id: id, fileName: url.lastPathComponent, fileURL: destFile))
                } catch {
                    try? FileManager.default.removeItem(at: destDir)
                    failures += 1
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let newItems = copied.map { ShelfItem(id: $0.id, fileName: $0.fileName, fileURL: $0.fileURL) }
                self.items.append(contentsOf: newItems)
                self.pendingAddCount -= 1
                if failures > 0 {
                    self.lastErrorMessage = failures == 1
                        ? "1 file failed to add"
                        : "\(failures) files failed to add"
                }
            }
        }
    }

    func removeItem(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        selectedIDs.remove(item.id)
        let dir = item.fileURL.deletingLastPathComponent()
        guard dir.standardizedFileURL.path.hasPrefix(storageURL.standardizedFileURL.path + "/") else { return }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            NSLog("DragDrop: Failed to remove item directory %@: %@", dir.path, error.localizedDescription)
        }
    }

    func removeSelected() {
        let toRemove = items.filter { selectedIDs.contains($0.id) }
        toRemove.forEach { removeItem($0) }
    }

    func requestRemoveSelected() {
        guard !selectedIDs.isEmpty else { return }
        if selectedIDs.count == items.count {
            showDeleteAllConfirmation = true
        } else {
            removeSelected()
        }
    }

    private func isOwnFile(_ url: URL) -> Bool {
        let normalizedStorage = storageURL.standardizedFileURL.path
        let normalizedURL = url.standardizedFileURL.path
        return normalizedURL == normalizedStorage || normalizedURL.hasPrefix(normalizedStorage + "/")
    }

    private func loadPersistedItems() {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var loaded: [ShelfItem] = []
        var staleDirectories: [URL] = []

        for directory in directories {
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
                continue
            }
            guard let uuid = UUID(uuidString: directory.lastPathComponent) else {
                staleDirectories.append(directory)
                continue
            }

            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ), let fileURL = files.first else {
                staleDirectories.append(directory)
                continue
            }

            if files.count > 1 {
                let extras = files.dropFirst()
                for extra in extras {
                    do {
                        try fileManager.removeItem(at: extra)
                    } catch {
                        NSLog("DragDrop: Failed to remove extra persisted file %@: %@", extra.path, error.localizedDescription)
                    }
                }
            }

            let createdAt = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            loaded.append(
                ShelfItem(id: uuid, fileName: fileURL.lastPathComponent, fileURL: fileURL, addedAt: createdAt)
            )
        }

        for directory in staleDirectories {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                NSLog("DragDrop: Failed to remove stale directory %@: %@", directory.path, error.localizedDescription)
            }
        }
        items = loaded.sorted { $0.addedAt < $1.addedAt }
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
