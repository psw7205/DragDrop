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

## Operating Rules

- `확인`, `검토`, `분석`, `리뷰` 요청은 read-only로 처리한다.
- `수정`, `구현`, `반영`, `업데이트`, `커밋`, `설치` 요청은 execution으로 처리한다.
- 앱 코드, 테스트, 빌드 설정, 배포 스크립트를 바꾸는 작업은 커밋하고 Release 빌드를 로컬에 설치하는 것까지 한 사이클이다.
- 위 작업에서 완료 보고 전 기본 순서는 `xcodebuild clean test -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug -destination 'platform=macOS'` → 관련 파일만 `git add` → `git commit` → `./install.sh` 이다.
- 문서만 바꾸는 작업은 `./install.sh` 대상이 아니다. 대신 diff 검증 후 관련 문서만 커밋한다.
- 검증을 실행하지 못하거나 설치하지 못하면 성공으로 말하지 말고, 실패한 단계와 남은 리스크를 명시한다.

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
