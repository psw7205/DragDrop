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
    @Published private(set) var pendingAddCount = 0

    var displayState: ShelfDisplayState {
        if isDragHovering { return .expanded }
        if isExternalDragging { return .indicator }
        if isManuallyHidden { return .hidden }
        if !items.isEmpty { return .expanded }
        if pendingAddCount > 0 { return .expanded }
        if lastErrorMessage != nil { return .expanded }
        if showDeleteAllConfirmation { return .expanded }
        if isManuallyExpanded { return .expanded }
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
}
