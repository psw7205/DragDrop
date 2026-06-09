# 2026-05-29 다음 기능 방향 — 간단 설계

## 목적

새 세션에서 바로 이어서 설계/구현 착수할 수 있도록 DragDrop의 다음 기능 후보 3개를 정리한다.

## 전제

- 여기서 1/2/3번은 직전 추천 목록 기준이다.
  1. `Settings + configurable cleanup`
  2. `Item context menu`
  3. `Search/sort + metadata`
- 이전에 제외한 3번 방향은 `Dropp`식 cloud sync / cross-device / backend 확장으로 보고 계속 제외한다.
- DragDrop의 핵심 제품 방향은 “우측 플로팅 shelf에 임시 보관”이다. notch UI로 전환하거나 cloud 제품으로 확장하지 않는다.

## 참고한 sibling 프로젝트

### `../NotchDrop`

- `NotchSettingsView.swift`
  - `Launch at Login`, `Haptic Feedback`, `File Storage Time`을 한 설정 화면에서 다룬다.
  - DragDrop은 기존 status menu에 흩어진 제어를 `Preferences` 창으로 모으는 방향을 참고할 수 있다.
- `TrayDrop.swift`
  - `FileStorageTime` enum으로 `1 Hour`, `1 Day`, `1 Week`, `Forever`, `Custom`을 표현한다.
  - DragDrop의 `ShelfCleanupPolicy.manualStorageCleanup`을 사용자 설정 기반 policy로 바꾸는 데 직접 참고 가능하다.
- `NotchMenuView.swift`
  - compact icon button으로 settings/clear 동작을 제공한다.
  - DragDrop은 panel 내부보다 status menu와 item context menu에 우선 적용하는 편이 제품 방향에 맞다.
- `TrayDrop+View.swift`
  - empty state에서 보관 시간 안내와 삭제 modifier affordance를 준다.
  - DragDrop도 설정된 보관 정책을 empty state 또는 settings에 명확히 노출할 수 있다.

### `../Dropp`

- `macos/Dropp/Dropp/Shelf.swift`
  - duplicate detection, item metadata, cloud state 모델이 있다.
  - DragDrop에는 cloud state는 가져오지 않고, local item metadata와 중복 방지 아이디어만 선별 참고한다.

## 현재 DragDrop 연결 지점

- `AppDelegate.swift`
  - status item, right-click menu, `Launch at Login`, `Clean Up Storage...`, `About`, `Quit`을 관리한다.
  - 새 `Preferences` 진입점과 context command wiring의 시작점이다.
- `ShelfStorage.swift`
  - `ShelfCleanupPolicy.manualStorageCleanup`이 현재 `30일 + 1GB` fixed policy다.
  - `storageMetrics()`와 `cleanup(using:)`이 이미 있어 설정 기반 cleanup으로 확장하기 좋다.
- `ShelfViewModel.swift`
  - `items`, `selectedIDs`, `cleanupStorage`, selection 동작을 관리한다.
  - context menu action과 search/sort 상태가 들어갈 가능성이 높다.
- `ShelfView.swift`
  - header, empty state, grid를 렌더링한다.
  - search field/sort control을 넣는다면 header 또는 grid 상단이 후보 지점이다.
- `ShelfItemView.swift`
  - item cell, delete button, `DragSourceView` overlay를 가진다.
  - item context menu와 metadata tooltip을 붙이기 좋은 위치다.

## 우선순위 요약

1. `Settings + configurable cleanup`
   - 최근 추가한 cleanup 기능을 사용자 제어 가능한 기능으로 완성한다.
   - 범위가 작고 테스트가 쉽다.
2. `Item context menu`
   - shelf item 조작성을 네이티브 macOS 앱답게 개선한다.
   - search/sort보다 작고 즉시 체감된다.
3. `Search/sort + metadata`
   - item 수가 많아졌을 때 필요한 탐색성 개선이다.
   - metadata 모델과 UI 상태가 필요하므로 1/2 이후가 적절하다.

---

# 1. Settings + configurable cleanup

## 의도

현재 fixed cleanup policy를 사용자가 이해하고 조정할 수 있게 만든다.

## 사용자 가치

- 사용자가 파일 보관 기간과 저장소 한도를 직접 선택할 수 있다.
- `Clean Up Storage...`가 “무엇을 지우는지” 설정 화면에서 먼저 설명된다.
- 임시 shelf라는 제품 성격을 유지하면서 저장소 불안을 줄인다.

## 제안 동작

- status menu에 `Preferences...` 항목을 추가한다.
- `Preferences` 창에서 다음 값을 설정한다.
  - `Launch at Login`
  - `Storage retention`: `1 Day`, `7 Days`, `30 Days`, `Forever`, `Custom`
  - `Storage size limit`: `Off`, `512 MB`, `1 GB`, `Custom`
  - `Clean Now`
  - 현재 저장 item 수와 total size
- `Clean Up Storage...`는 설정된 policy를 사용한다.
- 기본값은 현재 동작과 동일하게 `30 days + 1 GB`로 둔다.

## 설계 방향

- `UserDefaults` 기반 설정 모델을 추가한다.
- 설정 모델은 UI 표시값과 `ShelfCleanupPolicy` 변환을 책임진다.
- cleanup 실행은 기존 `ShelfViewModel.cleanupStorage(using:)` 경로를 유지한다.
- `AppDelegate`는 menu entry와 window presentation만 담당한다.

## 검증 기준

- 기본 설정에서 기존 cleanup 동작이 유지된다.
- retention을 `Forever`로 바꾸면 age 기준 삭제가 비활성화된다.
- size limit을 `Off`로 바꾸면 용량 기준 삭제가 비활성화된다.
- `Clean Now` 후 item 목록과 storage metrics가 일관되게 갱신된다.

## 리스크

- custom 값 검증이 느슨하면 `0 day`, 음수, 지나치게 큰 값이 저장될 수 있다.
- settings window lifecycle이 `AppDelegate`에 과도하게 쌓이면 유지보수가 어려워진다.

## 추천

추천: 1번부터 진행 — 이미 있는 cleanup code를 제품 기능으로 닫는 작업이고, sibling `NotchDrop`에서 가장 직접적인 참고 사례가 있다.

---

# 2. Item context menu

## 의도

각 shelf item의 기본 조작을 delete button과 keyboard shortcut에만 의존하지 않게 한다.

## 사용자 가치

- macOS 사용자가 기대하는 right-click workflow를 제공한다.
- `Open`, `Reveal in Finder`, `Quick Look`, `Delete` 같은 동작이 발견 가능해진다.
- 다중 선택 상태에서 일괄 조작을 더 명확히 할 수 있다.

## 제안 동작

- item 우클릭 시 context menu를 표시한다.
- 단일 item 메뉴:
  - `Open`
  - `Quick Look`
  - `Reveal in Finder`
  - `Copy`
  - `Delete`
- 다중 선택 중 선택 item을 우클릭하면:
  - `Quick Look Selected`
  - `Copy Selected`
  - `Delete Selected`
- 선택되지 않은 item을 우클릭하면 해당 item을 단일 선택한 뒤 메뉴를 연다.

## 설계 방향

- `ShelfItemView`에 SwiftUI `.contextMenu`를 붙이는 방향을 우선 검토한다.
- 실제 command 실행은 `ShelfViewModel` 또는 `AppDelegate` 경유로 분리한다.
- Quick Look은 현재 `AppDelegate.toggleQuickLook()` 경로와 충돌하지 않게 연결한다.
- delete는 기존 `removeItem`, `requestRemoveSelected` 경로를 재사용한다.

## 검증 기준

- 우클릭이 drag-out 동작을 깨지 않는다.
- 선택되지 않은 item 우클릭 시 메뉴 대상이 명확하다.
- 다중 선택 후 `Delete Selected`가 기존 전체 삭제 confirmation 정책을 유지한다.
- `Reveal in Finder`는 저장된 복사본 위치를 연다.

## 리스크

- `DragSourceView` overlay가 mouse event를 잡고 있어서 SwiftUI context menu와 충돌할 수 있다.
- Quick Look은 `QLPreviewPanel` ownership이 `AppDelegate`에 있어 wiring을 단순하게 유지해야 한다.

## 추천

추천: 1번 다음에 진행 — 구현 범위가 작고, native app 체감 품질을 바로 올린다.

---

# 3. Search/sort + metadata

## 의도

shelf item이 많아졌을 때 찾기와 정리를 빠르게 만든다.

## 사용자 가치

- 파일명, link host, text snippet 기준으로 빠르게 찾을 수 있다.
- 오래된 항목, 큰 항목, 특정 타입 항목을 쉽게 파악할 수 있다.
- cleanup 설정과 함께 “무엇이 저장돼 있는지”에 대한 신뢰를 높인다.

## 제안 동작

- expanded shelf header 또는 grid 상단에 compact search field를 추가한다.
- sort option은 menu 또는 compact control로 제공한다.
  - `Added`
  - `Name`
  - `Kind`
  - `Size`
- item tooltip 또는 compact metadata line에 다음 정보를 표시한다.
  - file size
  - added date
  - content kind
  - link original URL host

## 설계 방향

- `ShelfItem` 또는 별도 metadata provider가 display metadata를 제공한다.
- `ShelfViewModel`은 `query`, `sortMode`, `visibleItems`를 제공한다.
- 원본 `items` 배열은 저장 순서와 reorder 의미를 보존한다.
- sort/search는 view projection으로 시작하고, persistence는 나중에 결정한다.
- `Dropp`의 cloud metadata 모델은 제외하고 local metadata만 참고한다.

## 검증 기준

- 검색어를 비우면 기존 item 순서가 복원된다.
- reorder와 sort mode의 관계가 명확하다.
  - 추천 기본값: sort mode가 `Manual`일 때만 drag reorder 활성화.
- link item은 original URL host로 검색된다.
- size/date metadata 조회가 UI scroll 성능을 눈에 띄게 떨어뜨리지 않는다.

## 리스크

- sort와 manual reorder를 동시에 허용하면 사용자 기대가 충돌한다.
- file size/date를 매 render마다 파일 시스템에서 읽으면 성능 문제가 생길 수 있다.
- UI가 좁은 200px shelf 안에서 복잡해질 수 있다.

## 추천

추천: 1/2번 이후 진행 — 가치가 있지만 모델과 UI 상태가 더 많이 늘어나므로, settings와 context menu로 기본 조작성을 먼저 닫는 편이 낫다.

---

# 새 세션 handoff

## 시작 시 확인할 것

1. `git status --short`
2. `docs/superpowers/specs/2026-05-29-next-feature-directions-design.md`
3. `DragDrop/AppDelegate.swift`
4. `DragDrop/ShelfStorage.swift`
5. `DragDrop/ShelfViewModel.swift`
6. `DragDrop/ShelfView.swift`
7. `DragDrop/ShelfItemView.swift`
8. 관련 테스트: `DragDropTests/ShelfStorageTests.swift`, `DragDropTests/ShelfViewModelTests.swift`

## 권장 착수 순서

1. 1번을 별도 implementation plan으로 쪼갠다.
2. 설정 모델과 cleanup policy 변환 테스트를 먼저 작성한다.
3. `Preferences` UI와 status menu entry를 붙인다.
4. release build 전에 전체 test + release build를 실행한다.
5. 1번 완료 후 2번 context menu를 별도 logical unit으로 진행한다.
6. 3번은 1/2번 후 item count와 UI 복잡도를 다시 보고 착수한다.

## 새 세션 시작 프롬프트 예시

`/Users/hc/Repository/etc/dragdrop/DragDrop`에서 `docs/superpowers/specs/2026-05-29-next-feature-directions-design.md`를 읽고, 1번 `Settings + configurable cleanup`부터 implementation plan 작성 후 순서대로 구현해줘. 3번은 cloud/cross-device가 아니라 search/sort + metadata 의미이고, Dropp의 cloud sync 방향은 제외해.
