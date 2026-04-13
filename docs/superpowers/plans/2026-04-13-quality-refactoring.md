# DragDrop 품질 개선 및 리팩터링 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DragDrop 앱의 내부 품질 개선 — ViewModel 역할 분리, 확장 가능한 컨텐츠 모델, 이벤트 기반 드래그 감지, 코드 견고성 강화.

**Architecture:** ShelfViewModel에서 파일 I/O(`ShelfStorage`)와 클립보드 읽기(`ClipboardService`)를 분리하고, `ShelfItem`을 `ShelfContent` enum 기반으로 재설계. `GlobalDragMonitor`는 타이머 폴링을 제거하고 Dropp 프로젝트 패턴(이벤트 핸들러 내 직접 체크)으로 전환.

**Tech Stack:** Swift, SwiftUI, AppKit, Combine

**Spec:** `docs/superpowers/specs/2026-04-13-quality-refactoring-design.md`

**테스트:** 테스트 타겟 없음. 각 태스크마다 `xcodebuild` 빌드 검증으로 대체.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `DragDrop/ShelfItem.swift` | Modify | `ShelfContent` enum 추가, computed property 변경 |
| `DragDrop/ShelfStorage.swift` | **Create** | 파일 I/O (복사, 삭제, 로드, 경로 관리) |
| `DragDrop/ClipboardService.swift` | **Create** | 시스템 클립보드 읽기 |
| `DragDrop/ShelfViewModel.swift` | Modify | I/O 제거, 서비스 주입, 오케스트레이터로 축소 |
| `DragDrop/GlobalDragMonitor.swift` | Modify | 타이머 제거, 이벤트 기반 전환 |
| `DragDrop/ShelfPanel.swift` | Modify | 매직넘버 → `kVK_*` 상수 |
| `DragDrop/AppDelegate.swift` | Modify | Combine 파이프라인 단순화 |
| `DragDrop/ShelfItemView.swift` | Modify | `item.fileName` → `item.displayName` |

---

### Task 1: ShelfContent enum + ShelfItem 리팩터링

**Files:**
- Modify: `DragDrop/ShelfItem.swift`
- Modify: `DragDrop/ShelfViewModel.swift` (construction sites only)
- Modify: `DragDrop/ShelfItemView.swift`

- [ ] **Step 1: Rewrite ShelfItem.swift — ShelfContent enum + 새 ShelfItem**

Replace entire file:

```swift
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
```

- [ ] **Step 2: Update ShelfViewModel construction sites**

`addFilesAsync` — change the `ShelfItem` construction in the `copied.map` closure:

```swift
// Before:
let newItems = copied.map { ShelfItem(id: $0.id, fileName: $0.fileName, fileURL: $0.fileURL) }
// After:
let newItems = copied.map { ShelfItem(id: $0.id, content: .file(url: $0.fileURL, fileName: $0.fileName)) }
```

`addData` — change the `items.append` call:

```swift
// Before:
self.items.append(ShelfItem(id: id, fileName: fileName, fileURL: destFile))
// After:
self.items.append(ShelfItem(id: id, content: .file(url: destFile, fileName: fileName)))
```

`loadPersistedItems` — change the `loaded.append` call:

```swift
// Before:
loaded.append(
    ShelfItem(id: uuid, fileName: fileURL.lastPathComponent, fileURL: fileURL, addedAt: createdAt)
)
// After:
loaded.append(
    ShelfItem(id: uuid, content: .file(url: fileURL, fileName: fileURL.lastPathComponent), addedAt: createdAt)
)
```

- [ ] **Step 3: Update ShelfItemView**

`ShelfItemView.swift` — change `item.fileName` to `item.displayName`:

```swift
// Before:
Text(item.fileName)
// After:
Text(item.displayName)
```

No other view changes needed — `item.fileURL`, `item.icon` remain available as computed properties.

- [ ] **Step 4: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add DragDrop/ShelfItem.swift DragDrop/ShelfViewModel.swift DragDrop/ShelfItemView.swift
git commit -m "refactor: ShelfContent enum 도입, ShelfItem을 다형적 컨텐츠 모델로 전환"
```

---

### Task 2: ShelfStorage 추출

**Files:**
- Create: `DragDrop/ShelfStorage.swift`
- Modify: `DragDrop/ShelfViewModel.swift`

- [ ] **Step 1: Create ShelfStorage.swift**

New file with all file I/O logic extracted from ShelfViewModel:

```swift
import Foundation
import AppKit

class ShelfStorage {
    let storageURL: URL

    init() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DragDrop/Items", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            NSLog("DragDrop: Failed to create storage directory: %@", error.localizedDescription)
        }
        self.storageURL = url
    }

    func copyFile(from url: URL) throws -> ShelfItem {
        let id = UUID()
        let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let destFile = destDir.appendingPathComponent(url.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destFile)
            return ShelfItem(id: id, content: .file(url: destFile, fileName: url.lastPathComponent))
        } catch {
            try? FileManager.default.removeItem(at: destDir)
            throw error
        }
    }

    func saveData(_ data: Data, fileName: String) throws -> ShelfItem {
        let id = UUID()
        let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let destFile = destDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try data.write(to: destFile)
            return ShelfItem(id: id, content: .file(url: destFile, fileName: fileName))
        } catch {
            try? FileManager.default.removeItem(at: destDir)
            throw error
        }
    }

    func removeItem(_ item: ShelfItem) {
        let dir = item.fileURL.deletingLastPathComponent()
        guard dir.standardizedFileURL.path.hasPrefix(storageURL.standardizedFileURL.path + "/") else { return }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            NSLog("DragDrop: Failed to remove item directory %@: %@", dir.path, error.localizedDescription)
        }
    }

    func loadPersistedItems() -> [ShelfItem] {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var loaded: [ShelfItem] = []
        var staleDirectories: [URL] = []

        for directory in directories {
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
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
                for extra in files.dropFirst() {
                    do {
                        try fileManager.removeItem(at: extra)
                    } catch {
                        NSLog("DragDrop: Failed to remove extra persisted file %@: %@",
                              extra.path, error.localizedDescription)
                    }
                }
            }

            let createdAt = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            loaded.append(
                ShelfItem(id: uuid, content: .file(url: fileURL, fileName: fileURL.lastPathComponent), addedAt: createdAt)
            )
        }

        for directory in staleDirectories {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                NSLog("DragDrop: Failed to remove stale directory %@: %@",
                      directory.path, error.localizedDescription)
            }
        }

        return loaded.sorted { $0.addedAt < $1.addedAt }
    }

    func isOwnFile(_ url: URL) -> Bool {
        let normalizedStorage = storageURL.standardizedFileURL.path
        let normalizedURL = url.standardizedFileURL.path
        return normalizedURL == normalizedStorage || normalizedURL.hasPrefix(normalizedStorage + "/")
    }
}
```

- [ ] **Step 2: Add ShelfStorage.swift to Xcode project**

Add the new file to the DragDrop target in `DragDrop.xcodeproj`.

- [ ] **Step 3: Update ShelfViewModel — inject storage, remove I/O logic**

Remove from ShelfViewModel:
- `storageURL` property and its initializer closure
- `loadPersistedItems()` method
- `isOwnFile(_:)` method
- File copy logic inside `addFilesAsync` (keep orchestration)
- File write logic inside `addData` (will be replaced in Task 3)
- File delete logic inside `removeItem` (keep orchestration)

Add to ShelfViewModel:

```swift
private let storage: ShelfStorage

init(storage: ShelfStorage = ShelfStorage()) {
    self.storage = storage
    loadPersistedItems()  // remove this method — call storage directly
}
```

Replace `init()`:

```swift
init(storage: ShelfStorage = ShelfStorage()) {
    self.storage = storage
    items = storage.loadPersistedItems()
}
```

Replace `addFilesAsync(from:)`:

```swift
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

private static func formatFailures(_ failures: [(String, Error)]) -> String {
    if failures.count == 1 {
        return "'\(failures[0].0)' 추가 실패: \(failures[0].1.localizedDescription)"
    }
    return "\(failures.count)개 파일 추가 실패"
}
```

Replace `removeItem(_:)`:

```swift
func removeItem(_ item: ShelfItem) {
    items.removeAll { $0.id == item.id }
    selectedIDs.remove(item.id)
    storage.removeItem(item)
}
```

Keep `addData` and `pasteFromClipboard` temporarily — they'll be replaced in Task 3.

- [ ] **Step 4: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add DragDrop/ShelfStorage.swift DragDrop/ShelfViewModel.swift DragDrop.xcodeproj
git commit -m "refactor: ShelfStorage 추출 — 파일 I/O를 ViewModel에서 분리"
```

---

### Task 3: ClipboardService 추출

**Files:**
- Create: `DragDrop/ClipboardService.swift`
- Modify: `DragDrop/ShelfViewModel.swift`

- [ ] **Step 1: Create ClipboardService.swift**

```swift
import AppKit

struct ClipboardService {
    enum Content {
        case files([URL])
        case image(Data, suggestedName: String)
        case text(String, suggestedName: String)
    }

    func read() -> Content? {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }

        let timestamp = Self.timestamp()

        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return .image(pngData, suggestedName: "Clipboard \(timestamp).png")
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text, suggestedName: "Clipboard \(timestamp).txt")
        }

        return nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: Date())
    }
}
```

- [ ] **Step 2: Add ClipboardService.swift to Xcode project**

Add the new file to the DragDrop target in `DragDrop.xcodeproj`.

- [ ] **Step 3: Update ShelfViewModel — inject clipboard, replace paste logic**

Add clipboard dependency:

```swift
private let storage: ShelfStorage
private let clipboard: ClipboardService

init(storage: ShelfStorage = ShelfStorage(), clipboard: ClipboardService = ClipboardService()) {
    self.storage = storage
    self.clipboard = clipboard
    items = storage.loadPersistedItems()
}
```

Replace `pasteFromClipboard()` and remove `addData(_:fileName:)` and `clipboardTimestamp()`:

```swift
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
```

- [ ] **Step 4: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add DragDrop/ClipboardService.swift DragDrop/ShelfViewModel.swift DragDrop.xcodeproj
git commit -m "refactor: ClipboardService 추출 — 클립보드 읽기를 ViewModel에서 분리"
```

---

### Task 4: GlobalDragMonitor 리라이트

**Files:**
- Modify: `DragDrop/GlobalDragMonitor.swift`
- Modify: `DragDrop/AppDelegate.swift`

**Reference:** `Dropp/macos/Dropp/Dropp/DroppApp.swift` — `FileDragStartObserver` 패턴

- [ ] **Step 1: Rewrite GlobalDragMonitor.swift**

Replace entire file. 타이머 제거, `leftMouseDragged` 이벤트 핸들러 내에서 `changeCount` 직접 비교:

```swift
import AppKit

class GlobalDragMonitor {
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var monitors: [Any] = []
    private var isDragging = false
    private var lastChangeCount: Int

    init() {
        lastChangeCount = NSPasteboard(name: .drag).changeCount
    }

    func start() {
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.handleDragged()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDragged()
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp()
            return event
        } as Any)
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        isDragging = false
    }

    private func handleDragged() {
        let pb = NSPasteboard(name: .drag)
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let types = pb.types ?? []
        guard types.contains(.fileURL) else { return }

        if !isDragging {
            isDragging = true
            onDragStarted?()
        }
    }

    private func handleMouseUp() {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 2: Update AppDelegate — add start() call**

In `setupDragMonitor()`, add `monitor.start()`:

```swift
private func setupDragMonitor() {
    let monitor = GlobalDragMonitor()
    monitor.onDragStarted = { [weak self] in
        self?.viewModel.isExternalDragging = true
    }
    monitor.onDragEnded = { [weak self] in
        self?.viewModel.isExternalDragging = false
    }
    monitor.start()
    self.dragMonitor = monitor
}
```

- [ ] **Step 3: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add DragDrop/GlobalDragMonitor.swift DragDrop/AppDelegate.swift
git commit -m "refactor: GlobalDragMonitor 타이머 제거, 이벤트 기반 드래그 감지로 전환"
```

---

### Task 5: ShelfPanel 매직넘버 제거

**Files:**
- Modify: `DragDrop/ShelfPanel.swift`

- [ ] **Step 1: Import Carbon.HIToolbox, replace keyCode literals**

Add import at top:

```swift
import Carbon.HIToolbox
```

Replace `performKeyEquivalent`:

```swift
override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
        switch Int(event.keyCode) {
        case kVK_ANSI_A:
            onSelectAll?()
            return true
        case kVK_ANSI_V:
            onPaste?()
            return true
        default:
            break
        }
    }
    return super.performKeyEquivalent(with: event)
}
```

Replace `keyDown`:

```swift
override func keyDown(with event: NSEvent) {
    switch Int(event.keyCode) {
    case kVK_Delete, kVK_ForwardDelete:
        onDeleteSelected?()
    default:
        super.keyDown(with: event)
    }
}
```

- [ ] **Step 2: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DragDrop/ShelfPanel.swift
git commit -m "refactor: ShelfPanel 매직넘버를 kVK_* 상수로 교체"
```

---

### Task 6: AppDelegate Combine 파이프라인 단순화

**Files:**
- Modify: `DragDrop/AppDelegate.swift`

- [ ] **Step 1: Replace MergeMany with objectWillChange**

In `setupPanel()`, replace the `geometryCancellable` assignment. Find:

```swift
geometryCancellable = Publishers.MergeMany(
    viewModel.$isExternalDragging.map { _ in () }.eraseToAnyPublisher(),
    viewModel.$isDragHovering.map { _ in () }.eraseToAnyPublisher(),
    viewModel.$items.map { _ in () }.eraseToAnyPublisher(),
    viewModel.$lastErrorMessage.map { _ in () }.eraseToAnyPublisher(),
    viewModel.$showDeleteAllConfirmation.map { _ in () }.eraseToAnyPublisher(),
    viewModel.$pendingAddCount.map { _ in () }.eraseToAnyPublisher(),
    viewModel.$isManuallyHidden.map { _ in () }.eraseToAnyPublisher(),
    viewModel.$isManuallyExpanded.map { _ in () }.eraseToAnyPublisher()
)
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        self?.updatePanelFrame()
        self?.updateStatusIcon()
    }
```

Replace with:

```swift
geometryCancellable = viewModel.objectWillChange
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        self?.updatePanelFrame()
        self?.updateStatusIcon()
    }
```

- [ ] **Step 2: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DragDrop/AppDelegate.swift
git commit -m "refactor: AppDelegate Combine 파이프라인을 objectWillChange로 단순화"
```

---

## Final ShelfViewModel (reference)

Tasks 1-3 완료 후 ShelfViewModel의 최종 모습:

```swift
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

    private let storage: ShelfStorage
    private let clipboard: ClipboardService

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

    init(storage: ShelfStorage = ShelfStorage(), clipboard: ClipboardService = ClipboardService()) {
        self.storage = storage
        self.clipboard = clipboard
        items = storage.loadPersistedItems()
    }

    // MARK: - Add Files

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

    private static func formatFailures(_ failures: [(String, Error)]) -> String {
        if failures.count == 1 {
            return "'\(failures[0].0)' 추가 실패: \(failures[0].1.localizedDescription)"
        }
        return "\(failures.count)개 파일 추가 실패"
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

    // MARK: - Remove

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
```
