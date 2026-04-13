# DragDrop 품질 개선 및 리팩터링 설계

## 목표

DragDrop 앱의 내부 품질을 개선한다. UI는 현행 유지. 구체적으로:

1. `ShelfViewModel` 역할 분리 (상태관리 / 파일 I/O / 클립보드)
2. `ShelfItem` 모델을 확장 가능한 컨텐츠 구조로 재설계
3. `GlobalDragMonitor` 타이머 폴링을 이벤트 기반으로 전환
4. 매직넘버 제거, 에러 처리 구체화, Combine 파이프라인 단순화

## 비목표

- UI/비주얼 변경
- 저장소 자동 정리 정책 (사용자가 직접 관리)
- 새 컨텐츠 타입의 실제 처리 로직 (구조만 준비)

## 1. 데이터 모델: ShelfItem + ShelfContent

### 현재

```
ShelfItem: id, fileName, fileURL, addedAt, icon(computed)
```

### 변경

```swift
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let content: ShelfContent
    let addedAt: Date

    var displayName: String   // content에서 파생
    var icon: NSImage         // content에서 파생
    var fileURL: URL?         // .file, .text, .image의 저장 URL
}

enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)
    case text(string: String, savedURL: URL)
    case image(savedURL: URL, originalName: String?)
}
```

- `enum`으로 컨텐츠 타입 표현. case 추가만으로 새 타입 지원.
- 현재는 `.file` case만 실제 사용. `.text`/`.image`는 클립보드 붙여넣기 시 분류에 사용.
- `displayName`, `icon`, `fileURL`은 content case별 switch로 파생.

## 2. 서비스 분리

### ShelfStorage (신규 파일)

파일 I/O 전담. `ShelfViewModel`에서 분리.

```
ShelfStorage {
    storageURL: URL

    addFiles(from: [URL]) async → (added: [ShelfItem], failures: [(fileName: String, error: Error)])
    addData(Data, fileName: String) async throws → ShelfItem
    removeItem(ShelfItem)
    loadPersistedItems() → [ShelfItem]
    isOwnFile(URL) → Bool
}
```

- `storageURL` 관리, 디렉터리 생성, 복사, 삭제 로직을 캡슐화.
- 비동기 파일 복사는 현행과 동일하게 `DispatchQueue.global(qos: .userInitiated)` 사용.
- 에러 시 실패한 파일명 + 원인을 포함하여 반환.

### ClipboardService (신규 파일)

시스템 클립보드 읽기 전담.

```
ClipboardService {
    paste() → ClipboardContent?

    enum ClipboardContent {
        case files([URL])
        case image(Data, suggestedName: String)
        case text(String, suggestedName: String)
    }
}
```

- `NSPasteboard.general`에서 읽기만 수행.
- 우선순위: files > image > text (현행과 동일).
- 파일명 생성 로직 (`clipboardTimestamp`) 포함.

### ShelfViewModel (축소)

```
ShelfViewModel {
    // 의존성
    storage: ShelfStorage
    clipboard: ClipboardService

    // 상태 (현행 유지)
    @Published items: [ShelfItem]
    @Published selectedIDs: Set<UUID>
    @Published isExternalDragging: Bool
    @Published isDragHovering: Bool
    @Published isManuallyHidden: Bool
    @Published isManuallyExpanded: Bool
    @Published lastErrorMessage: String?
    @Published showDeleteAllConfirmation: Bool
    @Published pendingAddCount: Int

    // 오케스트레이션
    addFilesAsync(from: [URL])     // storage 호출 + 상태 업데이트
    pasteFromClipboard()           // clipboard 읽기 + storage 저장 + 상태 업데이트
    removeItem/removeSelected()    // storage 삭제 + 상태 업데이트
    toggleShelf/selectAll/...      // 순수 상태 로직 (현행 유지)

    // computed (현행 유지)
    displayState: ShelfDisplayState
    expandedHeight: CGFloat
}
```

## 3. GlobalDragMonitor 개선

### 현재 문제

- 타이머 2개 (checkTimer 0.12초, endCheckTimer 0.15초)로 pasteboard 폴링
- 매 틱마다 `readObjects(forClasses:)` 호출 가능

### 변경: Dropp 방식 채택

ref: `Dropp/macos/Dropp/Dropp/DroppApp.swift` — `FileDragStartObserver`

```
GlobalDragMonitor {
    // 이벤트 모니터
    globalDragMonitor   // leftMouseDragged
    globalUpMonitor     // leftMouseUp
    localDragMonitor    // leftMouseDragged (로컬)
    localUpMonitor      // leftMouseUp (로컬)

    // 상태
    isDragging: Bool
    lastChangeCount: Int

    // 콜백
    onDragStarted: (() -> Void)?
    onDragEnded: (() -> Void)?
}
```

동작:
1. `leftMouseDragged` 이벤트 수신
2. `NSPasteboard(name: .drag).changeCount` 비교 — 변경 없으면 무시
3. changeCount 변경 시 `pb.types`에 `.fileURL` 있는지 확인
4. 파일 드래그면 `isDragging = true`, `onDragStarted` 콜백
5. `leftMouseUp` 이벤트 → `isDragging`이면 `onDragEnded` 콜백

타이머: 없음. `start()` / `stop()` 메서드로 lifecycle 명확화.

## 4. 코드 견고성

### ShelfPanel — 매직넘버 제거

```swift
import Carbon.HIToolbox

// 변경 전: case 0, case 9, case 51, case 117
// 변경 후:
case kVK_ANSI_A:                           // Cmd+A
case kVK_ANSI_V:                           // Cmd+V
case kVK_Delete, kVK_ForwardDelete:        // Delete
```

### 에러 처리 구체화

- `ShelfStorage.addFiles`가 성공 아이템과 실패 목록(파일명 + 에러)을 함께 반환
- `ShelfViewModel`이 failures를 `lastErrorMessage`에 구체적으로 표시
  - 예: `"'document.pdf' 추가 실패: The file couldn't be copied."`
- `ShelfStorage`가 `ShelfContent` enum을 사용하여 `ShelfItem`을 생성 (컨텐츠 타입 결정은 storage 레이어 책임)

### AppDelegate Combine 파이프라인 단순화

변경 전: 8개 publisher를 `MergeMany`로 수동 merge

변경 후:
```swift
viewModel.objectWillChange
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        self?.updatePanelFrame()
        self?.updateStatusIcon()
    }
```

`@Published` 프로퍼티들이 이미 `objectWillChange`를 트리거하므로 수동 merge 불필요.

## 파일 변경 요약

| 파일 | 변경 |
|---|---|
| `ShelfItem.swift` | `ShelfContent` enum 추가, computed 프로퍼티 변경 |
| `ShelfStorage.swift` (신규) | 파일 I/O 분리 |
| `ClipboardService.swift` (신규) | 클립보드 읽기 분리 |
| `ShelfViewModel.swift` | storage/clipboard 주입, I/O 로직 제거 |
| `GlobalDragMonitor.swift` | 타이머 제거, 이벤트 기반으로 전환 |
| `ShelfPanel.swift` | `kVK_*` 상수 사용 |
| `AppDelegate.swift` | Combine 파이프라인 단순화, 의존성 조립 |
| `ShelfView.swift` | ShelfItem API 변경에 따른 최소 수정 |
| `ShelfItemView.swift` | ShelfItem API 변경에 따른 최소 수정 |
