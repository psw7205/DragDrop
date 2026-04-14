# B2 전역 단축키 — 설계

## 목표

어디서든 `⌥⇧D` (Option+Shift+D)로 셸프를 토글한다.

## 동작

- 셸프가 숨겨져 있으면 → 표시 + 앱 활성화 + 패널 key window
- 셸프가 표시 중이면 → 숨기기
- 현재 `statusItemClicked`과 동일한 로직

## 구현

`AppDelegate`에 글로벌 + 로컬 이벤트 모니터 등록.

### 모니터

- `globalHotkeyMonitor`: `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` — 앱 비활성 시
- `localHotkeyMonitor`: `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` — 앱 활성 시

### 감지 조건

- `event.modifierFlags`에 `.option`과 `.shift`가 모두 포함
- `.command`, `.control`은 미포함 (다른 단축키와 충돌 방지)
- `event.keyCode == kVK_ANSI_D`

### 메서드

- `setupGlobalHotkey()`: 앱 시작 시 모니터 등록
- `toggleShelfFromHotkey()`: `viewModel.toggleShelf()` + 앱 활성화 + 패널 key

### 해제

`deinit`에서 `NSEvent.removeMonitor()` 호출.

## 변경 파일

| 파일 | 변경 |
|------|------|
| `AppDelegate.swift` | 모니터 프로퍼티, `setupGlobalHotkey()`, `toggleShelfFromHotkey()`, deinit 확장 |

## 변경하지 않는 파일

나머지 모든 파일 기존 동작 유지.
