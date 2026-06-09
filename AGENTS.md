# AGENTS.md — DragDrop

## Overview

화면 우측에 플로팅 셸프 패널을 표시하여 파일을 임시 보관하는 macOS 유틸리티 앱.
파일을 드래그&드롭으로 셸프에 넣고, 다시 드래그하여 다른 앱으로 꺼낼 수 있다.

## Build

```bash
open DragDrop.xcodeproj  # Xcode에서 ⌘R
```

- macOS 타겟, Swift/SwiftUI
- `DragDropTests` 테스트 타겟 있음

## Architecture

SwiftUI + AppKit 하이브리드, MVVM 패턴.

### 핵심 흐름

1. `AppDelegate` — 앱 진입점. `ShelfPanel` + `GlobalDragMonitor` 초기화
2. `GlobalDragMonitor` — 시스템 전역 마우스 이벤트 감지 (드래그 시작/종료)
3. `ShelfViewModel` — 상태 관리 (`items`, `selectedIDs`, `displayState`)
4. `ShelfPanel` — borderless NSPanel, 항상 최상위에 떠 있음
5. `ShelfHostingView` — NSHostingView 래퍼, 파일 드롭 수신 처리
6. `ShelfView` → `ShelfItemView` — SwiftUI UI 계층
7. `DragSourceView` — 셸프 아이템을 외부로 드래그 아웃 (NSViewRepresentable)
8. `WindowDragView` — 패널 헤더 드래그로 위치 이동

### 상태 전이 (ShelfDisplayState)

- `hidden` — 아이템 없고 드래그 없음
- `indicator` — 외부 드래그 감지됨 (아이콘만 표시)
- `expanded` — 호버 중이거나 아이템 있음 (전체 셸프 표시)

### 파일 저장

`~/Library/Application Support/DragDrop/Items/{UUID}/` 에 파일 복사본 저장.

## Code Style

- 4 스페이스 들여쓰기
- PascalCase 파일명
- early return + guard문
- weak 참조 + 캡처 리스트로 순환 참조 방지
