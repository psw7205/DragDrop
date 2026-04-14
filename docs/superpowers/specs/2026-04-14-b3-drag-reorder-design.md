# B3 드래그 리오더 — 설계

## 목표

셸프 아이템을 드래그하여 순서를 변경한다. 기존 외부 드래그 아웃 기능은 유지.

## 커스텀 Pasteboard 타입

```swift
extension NSPasteboard.PasteboardType {
    static let shelfItemID = NSPasteboard.PasteboardType("com.dragdrop.shelf-item")
}
```

내부 아이템 식별용. 파일 URL과 함께 pasteboard에 기록하여, 셸프 내 드롭 시 리오더로 처리.

## DragSourceView 확장

- `itemID: UUID` 파라미터 추가
- `mouseDragged`에서 기존 `NSDraggingItem(pasteboardWriter: url as NSURL)` 외에, 별도 `NSPasteboardItem`에 아이템 ID를 `.shelfItemID` 타입으로 작성하여 dragging session에 포함

## ShelfHostingView 리오더 감지

- `registerForDraggedTypes`에 `.shelfItemID` 추가
- `performDragOperation`에서 `.shelfItemID` 타입 데이터 우선 체크:
  - 있으면 → 내부 리오더: 드롭 위치에서 타겟 인덱스 계산 → `onItemReordered?(sourceID, targetIndex)` 호출
  - 없으면 → 기존 외부 드롭 처리 (file URL / web URL)
- `onItemReordered: ((UUID, Int) -> Void)?` 콜백 추가

### 드롭 위치 → 인덱스 변환

`ShelfLayout` 상수(`gridPadding`, `itemWidth`, `itemHeight`, `gridSpacing`, `columns`, `headerHeight`)와 드롭 좌표를 사용하여 row/column 계산 → index.
범위 밖이면 배열 끝으로 이동.

## ShelfViewModel

`moveItem(withID:toIndex:)` 메서드:
- items 배열에서 해당 ID의 아이템을 찾아 새 인덱스로 이동
- 경계값 클램핑 (0...items.count-1)

## AppDelegate

`hostingView.onItemReordered` 콜백을 `viewModel.moveItem(withID:toIndex:)` 에 연결.

## 변경 파일

| 파일 | 변경 |
|------|------|
| `DragSourceView.swift` | `itemID` 파라미터, pasteboard에 ID 작성 |
| `ShelfHostingView.swift` | `.shelfItemID` 타입 등록, 리오더 감지, 콜백 |
| `ShelfItemView.swift` | `DragSourceView`에 `itemID` 전달 |
| `ShelfViewModel.swift` | `moveItem(withID:toIndex:)` |
| `AppDelegate.swift` | `onItemReordered` 콜백 연결 |

## 변경하지 않는 파일

`ShelfItem`, `ShelfStorage`, `ClipboardService`, `ShelfPanel`, `GlobalDragMonitor`, `ShelfView` — 기존 동작 유지.
