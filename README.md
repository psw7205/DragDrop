# DragDrop

화면 우측에 떠 있는 플로팅 셸프에 파일을 드래그&드롭으로 임시 보관하는 macOS 유틸리티.
여러 앱 사이에서 파일을 옮길 때, 셸프를 중간 거치대로 활용할 수 있다.

## Features

- **플로팅 셸프** — 화면 우측에 항상 떠 있는 borderless 패널 (Dock 아이콘 없음)
- **자동 표시/숨김** — 파일 드래그 감지 시 indicator 표시, 호버 시 셸프 확장, 비어 있으면 자동 숨김
- **드래그 인** — 파일을 셸프 위에 드롭하면 복사본 저장
- **링크 저장** — 웹 URL 드롭 시 `.webloc` 파일로 저장
- **드래그 아웃** — 셸프 아이템을 드래그해서 다른 앱으로 전달
- **다중 선택** — ⌘+클릭으로 여러 파일 선택 후 일괄 드래그
- **패널 이동** — 헤더 영역 드래그로 패널 위치 조정
- **보관 파일 정리** — 메뉴바 우클릭 메뉴에서 30일 초과 항목과 1GB 초과 보관 파일 정리
- **모든 Space에서 동작** — 가상 데스크톱 전환해도 항상 표시

## Requirements

- macOS 13.0+
- Xcode 26.2+

## Build & Run

```bash
open DragDrop.xcodeproj
# Xcode에서 ⌘R
```

### 로컬 빌드 & 실행

```bash
script/build_and_run.sh
```

- 기본값은 `Debug` configuration과 현재 Mac architecture다.
- 실행 없이 빌드만 확인하려면 `BUILD_ONLY=1 script/build_and_run.sh`를 사용한다.
- `CONFIGURATION`, `DESTINATION`, `DERIVED_DATA_PATH` 환경 변수로 빌드 설정을 덮어쓸 수 있다.

### 릴리즈 빌드 & 설치

```bash
xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/DragDrop-*/Build/Products/Release/DragDrop.app /Applications/
```

## How It Works

```
┌─────────────────────────────────────────────────────┐
│  다른 앱에서 파일 드래그 시작                           │
│         │                                           │
│         ▼                                           │
│  GlobalDragMonitor가 드래그 감지                      │
│  (NSPasteboard.drag의 changeCount 변화 + drop type)  │
│         │                                           │
│         ▼                                           │
│  ┌─────────┐   호버   ┌──────────┐                   │
│  │indicator │ ------→ │ expanded │  ← 아이템 있으면   │
│  │(아이콘)  │ ←------ │ (셸프)   │    항상 이 상태    │
│  └─────────┘  벗어남  └──────────┘                   │
│       │                    │                         │
│       │ 드래그 종료         │ 파일 드롭                │
│       ▼                    ▼                         │
│  ┌────────┐          파일 복사본 저장                  │
│  │ hidden │          그리드에 표시                     │
│  └────────┘                                         │
└─────────────────────────────────────────────────────┘
```

### 상세 흐름

1. **앱 시작** — `AppDelegate`가 `ShelfPanel`(투명 borderless NSPanel)과 `GlobalDragMonitor`를 초기화
2. **드래그 감지** — `GlobalDragMonitor`가 `leftMouseDragged` 이벤트와 `NSPasteboard.drag`의 `changeCount` 변화를 감시하고, `fileURL`, `URL`, legacy filename 타입을 확인
3. **indicator 표시** — 파일 드래그가 확인되면 화면 우측에 60×60 아이콘 표시
4. **셸프 확장** — 패널 위로 호버하면 `ShelfHostingView`가 `draggingEntered`를 수신, 200px 너비의 셸프로 확장
5. **파일 저장** — 드롭된 파일은 `~/Library/Application Support/DragDrop/Items/{UUID}/`에 복사본으로 저장하고, 웹 URL은 `.webloc` 파일로 저장
6. **드래그 아웃** — `DragSourceView`(NSViewRepresentable)가 `NSDraggingSource`를 구현, 4px 이상 드래그하면 드래그 세션 시작
7. **마우스 업** — 드래그 없이 클릭하면 선택 처리 (⌘+클릭으로 다중 선택)

## Architecture

SwiftUI + AppKit 하이브리드, MVVM 패턴.

### 프로젝트 구조

```
DragDrop/
├── DragDropApp.swift        # @main, AppDelegate 연결
├── AppDelegate.swift        # 앱 진입점 — 패널·모니터 초기화, 상태 변화에 따른 프레임 업데이트
├── ShelfViewModel.swift     # 상태 관리 (items, selectedIDs, displayState)
├── ShelfPanel.swift         # borderless NSPanel — statusBar+1 레벨, 모든 Space에서 표시
├── ShelfHostingView.swift   # NSHostingView 래퍼 — 파일 드롭 수신 (NSDraggingDestination)
├── GlobalDragMonitor.swift  # 시스템 전역 마우스 이벤트 감지 — 파일/URL 드래그 시작·종료 콜백
├── ShelfView.swift          # SwiftUI — 상태별 UI (hidden/indicator/expanded)
├── ShelfItemView.swift      # SwiftUI — 개별 아이템 셀 (아이콘 + 파일명 + 삭제 버튼)
├── ShelfItem.swift          # 모델 — id, fileName, fileURL, icon, addedAt
├── DragSourceView.swift     # NSViewRepresentable — 셸프→외부 드래그 아웃 구현
├── WindowDragView.swift     # NSViewRepresentable — 패널 헤더 드래그 이동
└── Assets.xcassets/         # 앱 아이콘, 색상 에셋
```

### 상태 전이 (ShelfDisplayState)

| 상태 | 조건 | 패널 크기 | 마우스 이벤트 |
|------|------|----------|-------------|
| `hidden` | 아이템 없음 + 드래그 없음 | — | 무시 (`ignoresMouseEvents = true`) |
| `indicator` | 외부 파일 드래그 감지됨 | 60×60 | 수신 |
| `expanded` | 호버 중이거나 아이템 있음 | 200×(160~480) | 수신 |

### 파일 저장 구조

```
~/Library/Application Support/DragDrop/Items/
├── {UUID-1}/
│   └── document.pdf        # 원본 파일의 복사본
├── {UUID-2}/
│   └── image.png
└── ...
```

아이템 삭제 시 해당 UUID 디렉토리 전체가 제거된다.
메뉴바 우클릭 메뉴의 `Clean Up Storage...`는 30일 초과 항목을 제거하고, 저장소가 1GB를 넘으면 오래된 항목부터 제거한다.

## Tech Stack

- **Swift / SwiftUI** — UI 계층 (ShelfView, ShelfItemView)
- **AppKit** — NSPanel, NSDraggingSource/Destination, 글로벌 이벤트 모니터링
- **Combine** — ViewModel 상태 변화 구독 (`objectWillChange` → 패널 프레임 업데이트)
