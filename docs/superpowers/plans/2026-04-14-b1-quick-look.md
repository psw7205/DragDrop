# B1 Quick Look 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 셸프 아이템 선택 후 스페이스바로 macOS Quick Look 미리보기를 실행한다.

**Architecture:** `ShelfPanel`에서 spacebar 이벤트 감지 → `AppDelegate`가 `QLPreviewPanel` data source/delegate 역할 수행. 선택 변경 시 자동 갱신.

**Tech Stack:** Swift, AppKit, QuickLookUI (QLPreviewPanel)

**Spec:** `docs/superpowers/specs/2026-04-14-b1-quick-look-design.md`

**테스트 타겟 없음** — 빌드 검증 + 수동 테스트.

---

### Task 1: ShelfPanel — 스페이스바 감지 + onQuickLook 콜백

**Files:**
- Modify: `DragDrop/ShelfPanel.swift`

- [ ] **Step 1: onQuickLook 콜백 프로퍼티 추가**

기존 콜백 프로퍼티들(L44-46) 옆에 추가:

```swift
var onQuickLook: (() -> Void)?
```

- [ ] **Step 2: keyDown에 스페이스바 분기 추가**

`keyDown(with:)` 메서드(L79-86)에 spacebar case 추가:

```swift
override func keyDown(with event: NSEvent) {
    switch Int(event.keyCode) {
    case kVK_Delete, kVK_ForwardDelete:
        onDeleteSelected?()
    case kVK_Space:
        onQuickLook?()
    default:
        super.keyDown(with: event)
    }
}
```

- [ ] **Step 3: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 커밋**

```bash
git add DragDrop/ShelfPanel.swift
git commit -m "feat(b1): ShelfPanel 스페이스바 감지 + onQuickLook 콜백"
```

---

### Task 2: AppDelegate — QLPreviewPanel 구현

**Files:**
- Modify: `DragDrop/AppDelegate.swift`

- [ ] **Step 1: import QuickLookUI 추가**

파일 상단에 추가:

```swift
import QuickLookUI
```

- [ ] **Step 2: QLPreviewPanel data source/delegate extension 추가**

`AppDelegate` 클래스 밖(파일 끝)에 extension으로 추가:

```swift
extension AppDelegate: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        viewModel.selectedItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index < viewModel.selectedItems.count else { return nil }
        return viewModel.selectedItems[index].fileURL as NSURL
    }
}
```

- [ ] **Step 3: toggleQuickLook 메서드 추가**

`AppDelegate` 클래스 내부에 추가:

```swift
private func toggleQuickLook() {
    guard !viewModel.selectedItems.isEmpty else { return }
    let panel = QLPreviewPanel.shared()!
    if panel.isVisible {
        panel.orderOut(nil)
    } else {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 4: setupPanel에서 onQuickLook 콜백 연결**

`setupPanel()` 메서드 내 `panel.onPaste` 설정 뒤에 추가:

```swift
panel.onQuickLook = { [weak self] in
    self?.toggleQuickLook()
}
```

- [ ] **Step 5: 선택 변경 시 Quick Look 갱신 구독 추가**

`setupPanel()` 내 기존 `geometryCancellable` 설정 근처에 새 구독 추가. 먼저 클래스에 프로퍼티 추가:

```swift
private var selectionCancellable: AnyCancellable?
```

`setupPanel()` 내 `geometryCancellable` 설정 뒤에:

```swift
selectionCancellable = viewModel.$selectedIDs
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        guard let self else { return }
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.dataSource = self
            panel.reloadData()
        }
    }
```

- [ ] **Step 6: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 7: 커밋**

```bash
git add DragDrop/AppDelegate.swift
git commit -m "feat(b1): QLPreviewPanel data source/delegate + 선택 변경 갱신"
```

---

### Task 3: 통합 빌드 검증 + 수동 테스트

- [ ] **Step 1: 클린 빌드**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug clean build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: 수동 테스트 체크리스트**

앱 실행 후 확인:
1. 파일을 셸프에 드래그 → 선택 → 스페이스바 → Quick Look 패널 표시
2. 스페이스바 다시 누르기 → Quick Look 패널 닫힘
3. 이미지 파일 Quick Look → 이미지 미리보기 정상
4. 텍스트 파일 Quick Look → 텍스트 미리보기 정상
5. .webloc 파일(링크) Quick Look → .webloc 미리보기 표시
6. 선택 변경 → Quick Look 패널 내용 갱신
7. 선택 없이 스페이스바 → 아무 동작 없음
