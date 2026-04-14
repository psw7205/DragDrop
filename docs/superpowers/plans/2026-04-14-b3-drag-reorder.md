# B3 드래그 리오더 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 셸프 아이템을 드래그하여 순서를 변경한다. 기존 외부 드래그 아웃 기능은 유지.

**Architecture:** 커스텀 pasteboard 타입으로 아이템 ID를 전송, ShelfHostingView에서 내부 드롭 감지 시 리오더.

**Tech Stack:** Swift, AppKit (NSDraggingSession, NSPasteboard)

**Spec:** `docs/superpowers/specs/2026-04-14-b3-drag-reorder-design.md`

**테스트 타겟 없음** — 빌드 검증 + 수동 테스트.

---

### Task 1: 커스텀 Pasteboard 타입 + DragSourceView 확장

**Files:**
- Modify: `DragDrop/DragSourceView.swift`

- [ ] **Step 1: 커스텀 pasteboard 타입 정의 + itemID 파라미터 추가**

파일 상단, `import` 뒤에 extension 추가. `DragSourceView`에 `itemID` 파라미터 추가:

```swift
extension NSPasteboard.PasteboardType {
    static let shelfItemID = NSPasteboard.PasteboardType("com.dragdrop.shelf-item")
}

struct DragSourceView: NSViewRepresentable {
    let urls: [URL]
    let icon: NSImage
    let itemID: UUID
    let onClick: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.urls = urls
        view.icon = icon
        view.itemID = itemID
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.icon = icon
        nsView.itemID = itemID
        nsView.onClick = onClick
    }
}
```

- [ ] **Step 2: DragSourceNSView에 itemID + pasteboard 작성 추가**

```swift
class DragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var icon = NSImage()
    var itemID = UUID()
    var onClick: ((NSEvent.ModifierFlags) -> Void)?

    private var dragOrigin: NSPoint?
    private var didDrag = false

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, !didDrag else { return }
        let current = event.locationInWindow
        guard hypot(current.x - origin.x, current.y - origin.y) > 4 else { return }

        didDrag = true
        dragOrigin = nil

        // 파일 URL 아이템들
        var items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(self.bounds, contents: self.icon)
            return item
        }

        // 아이템 ID (리오더용)
        let idItem = NSPasteboardItem()
        idItem.setString(itemID.uuidString, forType: .shelfItemID)
        let draggingItem = NSDraggingItem(pasteboardWriter: idItem)
        draggingItem.setDraggingFrame(self.bounds, contents: self.icon)
        items.append(draggingItem)

        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?(event.modifierFlags)
        }
        dragOrigin = nil
        didDrag = false
    }
}
```

주요 변경점:
- `sourceOperationMaskFor`: `withinApplication`이면 `.move`, 외부면 `.copy`
- `mouseDragged`: 파일 URL + 커스텀 타입(아이템 ID)을 함께 전송

- [ ] **Step 3: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: 빌드 실패 가능 — ShelfItemView에서 `DragSourceView`에 `itemID` 전달 안 하므로. Task 2에서 수정.

컴파일 에러가 나면 Task 2에서 함께 수정.

- [ ] **Step 4: 커밋 (빌드 실패하면 Task 2와 함께)**

```bash
git add DragDrop/DragSourceView.swift
```

---

### Task 2: ShelfItemView — itemID 전달

**Files:**
- Modify: `DragDrop/ShelfItemView.swift`

- [ ] **Step 1: DragSourceView 호출에 itemID 추가**

현재 코드 (ShelfItemView body 내):
```swift
DragSourceView(
    urls: dragURLs,
    icon: item.icon,
    onClick: onTap
)
```

변경:
```swift
DragSourceView(
    urls: dragURLs,
    icon: item.icon,
    itemID: item.id,
    onClick: onTap
)
```

- [ ] **Step 2: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Task 1과 함께 커밋**

```bash
git add DragDrop/DragSourceView.swift DragDrop/ShelfItemView.swift
git commit -m "feat(b3): DragSourceView에 itemID 추가 + pasteboard 전송"
```

---

### Task 3: ShelfViewModel — moveItem 메서드

**Files:**
- Modify: `DragDrop/ShelfViewModel.swift`

- [ ] **Step 1: moveItem(withID:toIndex:) 메서드 추가**

`removeSelected()` 메서드 뒤에 추가:

```swift
func moveItem(withID id: UUID, toIndex targetIndex: Int) {
    guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
    let clamped = min(max(targetIndex, 0), items.count - 1)
    guard sourceIndex != clamped else { return }
    let item = items.remove(at: sourceIndex)
    items.insert(item, at: clamped)
}
```

- [ ] **Step 2: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: 커밋**

```bash
git add DragDrop/ShelfViewModel.swift
git commit -m "feat(b3): ViewModel moveItem(withID:toIndex:)"
```

---

### Task 4: ShelfHostingView — 리오더 감지 + AppDelegate 연결

**Files:**
- Modify: `DragDrop/ShelfHostingView.swift`
- Modify: `DragDrop/AppDelegate.swift`

- [ ] **Step 1: ShelfHostingView에 리오더 콜백 + 드래그 타입 등록**

콜백 프로퍼티 추가:
```swift
var onItemReordered: ((UUID, Int) -> Void)?
```

`registerForDraggedTypes` 변경:
```swift
registerForDraggedTypes([.fileURL, .URL, .shelfItemID])
```

- [ ] **Step 2: performDragOperation에 리오더 분기 추가**

`performDragOperation` 메서드를 전체 교체:

```swift
override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let pasteboard = sender.draggingPasteboard

    // 내부 리오더 체크 (최우선)
    if let idString = pasteboard.string(forType: .shelfItemID),
       let sourceID = UUID(uuidString: idString) {
        let location = convert(sender.draggingLocation, from: nil)
        let targetIndex = gridIndex(from: location)
        onItemReordered?(sourceID, targetIndex)
        return true
    }

    // file URL
    if let fileURLs = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL], !fileURLs.isEmpty {
        onFilesDropped?(fileURLs)
        return true
    }

    // non-file URL (웹 링크)
    if let urls = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: false]
    ) as? [URL], let webURL = urls.first,
       let scheme = webURL.scheme, ["http", "https"].contains(scheme.lowercased()) {
        onLinkDropped?(webURL)
        return true
    }

    return false
}
```

- [ ] **Step 3: gridIndex(from:) 헬퍼 추가**

`ShelfHostingView` 내에 추가:

```swift
private func gridIndex(from point: NSPoint) -> Int {
    let headerHeight: CGFloat = ShelfLayout.headerHeight
    let padding: CGFloat = ShelfLayout.gridPadding
    let itemW: CGFloat = ShelfLayout.itemWidth
    let itemH: CGFloat = ShelfLayout.itemHeight
    let spacing: CGFloat = ShelfLayout.gridSpacing
    let columns = ShelfLayout.columns

    // 뷰 좌표계: 좌하단 원점. 헤더는 상단.
    let viewHeight = bounds.height
    let y = viewHeight - point.y // 상단 기준으로 변환
    let contentY = y - headerHeight - padding
    let x = point.x - padding

    guard contentY >= 0, x >= 0 else { return 0 }

    let col = min(Int(x / (itemW + spacing)), columns - 1)
    let row = Int(contentY / (itemH + spacing))
    return row * columns + col
}
```

- [ ] **Step 4: draggingUpdated에서 리오더 시 .move 반환**

기존 `draggingUpdated` 메서드 교체:

```swift
override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    if sender.draggingPasteboard.types?.contains(.shelfItemID) == true {
        return .move
    }
    return .copy
}
```

- [ ] **Step 5: AppDelegate에서 onItemReordered 콜백 연결**

`AppDelegate.setupPanel()`에서 `hostingView.onLinkDropped` 블록 뒤에 추가:

```swift
hostingView.onItemReordered = { [weak self] sourceID, targetIndex in
    self?.viewModel.moveItem(withID: sourceID, toIndex: targetIndex)
    self?.viewModel.isDragHovering = false
    self?.viewModel.isExternalDragging = false
}
```

- [ ] **Step 6: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 7: 커밋**

```bash
git add DragDrop/ShelfHostingView.swift DragDrop/AppDelegate.swift
git commit -m "feat(b3): ShelfHostingView 리오더 감지 + AppDelegate 연결"
```

---

### Task 5: 통합 빌드 검증 + 수동 테스트

- [ ] **Step 1: 클린 빌드**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug clean build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: 수동 테스트 체크리스트**

1. 셸프에 파일 3-4개 드래그 추가
2. 아이템을 다른 위치로 드래그 → 순서 변경됨
3. 아이템을 셸프 밖으로 드래그 → 기존 파일 전달 동작 유지
4. 외부에서 파일을 셸프로 드래그 → 기존 추가 동작 유지
5. URL을 셸프로 드래그 → 링크 추가 동작 유지
6. 앱 재시작 → 변경된 순서 유지되지 않음 (items는 addedAt 순으로 로드, 이는 의도된 동작)
