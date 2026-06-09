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
    @Published var isManuallyHidden = false
    @Published var isManuallyExpanded = false
    @Published var lastErrorMessage: String?
    @Published var showDeleteAllConfirmation = false
    @Published var query = ""
    @Published var sortMode: ShelfSortMode = .manual
    @Published private(set) var pendingAddCount = 0

    var displayState: ShelfDisplayState {
        if isDragHovering { return .expanded }
        if isManuallyHidden { return isExternalDragging ? .indicator : .hidden }
        if !items.isEmpty { return .expanded }
        if pendingAddCount > 0 { return .expanded }
        if lastErrorMessage != nil { return .expanded }
        if showDeleteAllConfirmation { return .expanded }
        if isManuallyExpanded { return .expanded }
        if isExternalDragging { return .indicator }
        return .hidden
    }

    var expandedHeight: CGFloat {
        if items.isEmpty { return ShelfLayout.minHeight }
        let rows = Int(ceil(Double(max(visibleItems.count, 1)) / Double(ShelfLayout.columns)))
        let gridHeight = CGFloat(rows) * ShelfLayout.itemHeight
            + CGFloat(max(0, rows - 1)) * ShelfLayout.gridSpacing
            + ShelfLayout.gridPadding * 2
        let chromeHeight = ShelfLayout.headerHeight + ShelfLayout.controlsHeight
        return min(max(chromeHeight + gridHeight, ShelfLayout.minHeight), ShelfLayout.maxHeight)
    }

    var visibleItems: [ShelfItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems: [ShelfItem]

        if trimmedQuery.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                metadata(for: item).searchText.range(
                    of: trimmedQuery,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
        }

        switch sortMode {
        case .manual:
            return filteredItems
        case .added:
            return filteredItems.sorted {
                if $0.addedAt != $1.addedAt { return $0.addedAt > $1.addedAt }
                return compareNames($0, $1)
            }
        case .name:
            return filteredItems.sorted(by: compareNames)
        case .kind:
            return filteredItems.sorted {
                let leftKind = metadata(for: $0).kind
                let rightKind = metadata(for: $1).kind
                let kindOrder = leftKind.localizedStandardCompare(rightKind)
                if kindOrder != .orderedSame { return kindOrder == .orderedAscending }
                return compareNames($0, $1)
            }
        case .size:
            return filteredItems.sorted {
                let leftSize = metadata(for: $0).sizeBytes
                let rightSize = metadata(for: $1).sizeBytes
                if leftSize != rightSize { return leftSize > rightSize }
                return compareNames($0, $1)
            }
        }
    }

    // MARK: - Storage

    private let storage: ShelfStorage
    private let clipboard: ClipboardService

    init(storage: ShelfStorage = ShelfStorage(), clipboard: ClipboardService = ClipboardService()) {
        self.storage = storage
        self.clipboard = clipboard
        items = storage.loadPersistedItems()
    }

    func addFilesAsync(from urls: [URL]) {
        let candidates = urls.filter { !storage.isOwnFile($0) }
        guard !candidates.isEmpty else { return }

        isManuallyHidden = false
        pendingAddCount += 1

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var added: [ShelfItem] = []
            var failures: [(String, Error)] = []

            for url in candidates {
                do {
                    let item = try self.storage.copyFile(from: url)
                    added.append(item)
                } catch {
                    failures.append((url.lastPathComponent, error))
                }
            }

            DispatchQueue.main.async {
                self.items.append(contentsOf: added)
                self.pendingAddCount -= 1
                if !failures.isEmpty {
                    self.lastErrorMessage = Self.formatFailures(failures)
                }
            }
        }
    }

    func addLinkAsync(from url: URL) {
        isManuallyHidden = false
        pendingAddCount += 1

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let item = try self.storage.saveLink(from: url)
                DispatchQueue.main.async {
                    self.items.append(item)
                    self.pendingAddCount -= 1
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = "링크 추가 실패: \(error.localizedDescription)"
                    self.pendingAddCount -= 1
                }
            }
        }
    }

    private static func formatFailures(_ failures: [(String, Error)]) -> String {
        if failures.count == 1 {
            return "'\(failures[0].0)' 추가 실패: \(failures[0].1.localizedDescription)"
        }
        return "\(failures.count)개 파일 추가 실패"
    }

    func removeItem(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        selectedIDs.remove(item.id)
        storage.removeItem(item)
    }

    func removeSelected() {
        let toRemove = items.filter { selectedIDs.contains($0.id) }
        toRemove.forEach { removeItem($0) }
    }

    @discardableResult
    func cleanupStorage(using policy: ShelfCleanupPolicy, now: Date = Date()) throws -> ShelfCleanupResult {
        let result = try storage.cleanup(using: policy, now: now)
        let removedIDs = Set(result.removedItemIDs)
        items.removeAll { removedIDs.contains($0.id) }
        selectedIDs.subtract(removedIDs)
        return result
    }

    func storageMetrics() throws -> ShelfStorageMetrics {
        try storage.storageMetrics()
    }

    func metadata(for item: ShelfItem) -> ShelfItemMetadata {
        ShelfItemMetadata.make(for: item)
    }

    func contextMenuItems(for targetID: UUID) -> [ShelfItem] {
        guard let target = items.first(where: { $0.id == targetID }) else { return [] }
        guard selectedIDs.contains(targetID) else {
            selectOnly(targetID)
            return [target]
        }
        return selectedItems
    }

    func dragItems(for sourceID: UUID) -> [ShelfItem] {
        guard let source = items.first(where: { $0.id == sourceID }) else { return [] }
        guard selectedIDs.contains(sourceID) else { return [source] }
        return selectedItems
    }

    func moveItem(withID id: UUID, toIndex targetIndex: Int) {
        moveItems(withIDs: [id], toIndex: targetIndex)
    }

    func moveItems(withIDs ids: [UUID], toIndex targetIndex: Int) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sortMode == .manual, trimmedQuery.isEmpty else { return }

        var seenIDs: Set<UUID> = []
        let uniqueIDs = ids.filter { seenIDs.insert($0).inserted }
        guard !uniqueIDs.isEmpty else { return }

        let idSet = Set(uniqueIDs)
        let movingItems = items.filter { idSet.contains($0.id) }
        guard !movingItems.isEmpty else { return }

        let remainingItems = items.filter { !idSet.contains($0.id) }
        let insertionIndex = min(max(targetIndex, 0), remainingItems.count)
        let reorderedItems = Array(remainingItems[..<insertionIndex])
            + movingItems
            + Array(remainingItems[insertionIndex...])

        guard reorderedItems.map(\.id) != items.map(\.id) else { return }
        items = reorderedItems
    }

    func requestRemoveSelected() {
        guard !selectedIDs.isEmpty else { return }
        if selectedIDs.count == items.count {
            showDeleteAllConfirmation = true
        } else {
            removeSelected()
        }
    }

    // MARK: - Toggle

    func toggleShelf() {
        if isManuallyHidden {
            isManuallyHidden = false
            if items.isEmpty && pendingAddCount == 0 {
                isManuallyExpanded = true
            }
        } else if displayState != .hidden {
            isManuallyHidden = true
            isManuallyExpanded = false
            showDeleteAllConfirmation = false
        } else {
            isManuallyExpanded = true
        }
    }

    // MARK: - Paste

    func pasteFromClipboard() {
        guard let content = clipboard.read() else { return }
        switch content {
        case .files(let urls):
            addFilesAsync(from: urls)
        case .image(let data, let name):
            saveDataAsync(data, fileName: name)
        case .text(let text, let name):
            guard let data = text.data(using: .utf8) else { return }
            saveDataAsync(data, fileName: name)
        case .url(let url):
            addLinkAsync(from: url)
        }
    }

    private func saveDataAsync(_ data: Data, fileName: String) {
        isManuallyHidden = false
        pendingAddCount += 1

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let item = try self.storage.saveData(data, fileName: fileName)
                DispatchQueue.main.async {
                    self.items.append(item)
                    self.pendingAddCount -= 1
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = "'\(fileName)' 붙여넣기 실패: \(error.localizedDescription)"
                    self.pendingAddCount -= 1
                }
            }
        }
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

    private func compareNames(_ lhs: ShelfItem, _ rhs: ShelfItem) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}
