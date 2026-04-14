# B1 Quick Look — 설계

## 목표

셸프 아이템을 선택하고 스페이스바를 누르면 macOS Quick Look으로 미리보기한다.

## 트리거

- `ShelfPanel.keyDown`에서 `kVK_Space` 감지 → `onQuickLook?()` 콜백 호출
- 선택된 아이템이 없으면 무시

## QLPreviewPanel 연결

`AppDelegate`에서 `QLPreviewPanelDataSource` + `QLPreviewPanelDelegate` 채택.

- `numberOfPreviewItems`: `viewModel.selectedItems.count` (0이면 Quick Look 패널 닫기)
- `previewItemAt index`: `viewModel.selectedItems[index].fileURL` 반환
- `URL`은 이미 `QLPreviewItem`을 준수하므로 별도 래퍼 불필요

## 토글 동작

- Quick Look 패널이 닫혀 있으면 열기 (`makeKeyAndOrderFront`)
- 이미 열려 있으면 닫기 (`orderOut`)

## 선택 변경 시

Quick Look 패널이 열려 있는 동안 선택이 변경되면 `reloadData`로 갱신.
`AppDelegate`에서 `viewModel.$selectedIDs` 구독하여 처리.

## 변경 파일

| 파일 | 변경 |
|------|------|
| `ShelfPanel.swift` | `kVK_Space` 감지, `onQuickLook` 콜백 |
| `AppDelegate.swift` | `QLPreviewPanelDataSource`/`Delegate` 구현, `onQuickLook` 연결, 선택 변경 구독 |

## 변경하지 않는 파일

`ShelfItem`, `ShelfStorage`, `ShelfViewModel`, `ShelfItemView`, `ShelfHostingView`, `ClipboardService`, `GlobalDragMonitor` — 기존 동작 유지.
