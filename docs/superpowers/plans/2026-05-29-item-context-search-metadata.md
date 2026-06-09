# Item Context Menu And Search Metadata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`로 task 단위 실행한다.

**Goal:** `2026-05-29-next-feature-directions-design.md`의 2번 `Item context menu`, 3번 `Search/sort + metadata`를 순서대로 완성한다.

**Architecture:** item context menu는 기존 `DragSourceView` AppKit overlay에서 `NSMenu`를 띄워 drag-out과 충돌하지 않게 한다. search/sort는 `ShelfViewModel`의 projection(`visibleItems`)으로 시작하고, 원본 `items` 배열은 manual reorder와 persistence 의미를 유지한다.

**Tech Stack:** Swift 5, SwiftUI, AppKit, QuickLookUI, XCTest.

---

## 성공 기준

- 선택되지 않은 item 우클릭 대상은 단일 선택으로 전환된다.
- 이미 선택된 item 우클릭은 기존 다중 선택을 유지한다.
- 단일 context menu는 `Open`, `Quick Look`, `Reveal in Finder`, `Copy`, `Delete`를 제공한다.
- 다중 선택 context menu는 `Quick Look Selected`, `Copy Selected`, `Delete Selected`를 제공한다.
- `Delete Selected`는 기존 `requestRemoveSelected()` 경로를 사용해 전체 삭제 confirmation 정책을 유지한다.
- 검색어를 비우면 기존 `items` 순서가 복원된다.
- link item은 original URL host로 검색된다.
- sort mode는 `Manual`, `Added`, `Name`, `Kind`, `Size`를 제공한다.
- manual mode에서만 reorder가 수행된다.
- item card와 tooltip은 file size, added date, content kind/link host 등 local metadata를 표시한다.
- 전체 test와 Debug build가 통과한다.

## 변경 파일

- Modify: `DragDrop/DragSourceView.swift`
  - right-click context menu 지원
- Modify: `DragDrop/ShelfItemView.swift`
  - context menu provider와 metadata tooltip 연결
- Modify: `DragDrop/ShelfView.swift`
  - context menu command wiring, search field, sort menu, `visibleItems` grid 사용
- Modify: `DragDrop/ShelfViewModel.swift`
  - context menu target selection, search query, sort mode, visible item projection, metadata provider, manual reorder guard
- Modify: `DragDrop/ShelfItem.swift`
  - sort mode 및 metadata value type 추가
- Modify: `DragDrop/ShelfHostingView.swift`
  - search/sort controls 높이를 고려한 reorder index 계산
- Modify: `DragDrop/AppDelegate.swift`
  - open/reveal/copy/quick look selected callbacks 추가
- Modify: `DragDropTests/ShelfViewModelTests.swift`
  - context menu selection, visible item projection, sort/search, manual reorder guard 테스트
## 실행 순서

- [x] 2번 context menu selection 테스트 RED
- [x] `ShelfViewModel.contextMenuItems(for:)` 구현 GREEN
- [x] `DragSourceView` right-click menu support와 `ShelfView`/`AppDelegate` command wiring 구현
- [x] 3번 metadata/search/sort 테스트 RED
- [x] metadata provider, `query`, `sortMode`, `visibleItems`, manual reorder guard 구현 GREEN
- [x] compact search/sort UI와 tooltip 연결
- [x] 전체 `xcodebuild test`와 `xcodebuild build` 검증
