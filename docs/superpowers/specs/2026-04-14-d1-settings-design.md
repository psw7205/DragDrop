# D1 설정 화면 — 설계

## 목표

메뉴바 아이콘에 컨텍스트 메뉴를 추가하여 앱 설정과 제어를 제공한다.

## 동작

- 메뉴바 아이콘 **클릭** → 셸프 토글 (기존 동작 유지)
- 메뉴바 아이콘 **우클릭** → 설정 메뉴 표시

## 메뉴 항목

1. **"Launch at Login"** — 토글, `SMAppService.mainApp`으로 로그인 항목 등록/해제
2. **구분선**
3. **"About DragDrop"** — 앱 이름 + 버전 표시 (alert)
4. **"Quit DragDrop"** — `NSApp.terminate(nil)`

## 구현

### AppDelegate 변경

- `setupStatusItem()`에서 `NSMenu` 생성하여 `statusItem.menu` 대신 **우클릭 시에만** 메뉴 표시
- `statusItem.button.sendAction(on: [.leftMouseUp, .rightMouseUp])` 설정
- `statusItemClicked`에서 이벤트 타입 분기:
  - 좌클릭 → 기존 `toggleShelf()` 로직
  - 우클릭 → `statusItem.menu` 설정 후 표시, 직후 `nil`로 복원 (좌클릭 시 메뉴가 뜨지 않도록)

### Launch at Login

- `import ServiceManagement`
- `SMAppService.mainApp.register()` / `unregister()`
- 메뉴 아이템 state로 현재 등록 상태 표시

## 변경 파일

| 파일 | 변경 |
|------|------|
| `AppDelegate.swift` | 메뉴 생성, 우클릭 분기, Launch at Login, About, Quit |

## 변경하지 않는 파일

나머지 모든 파일 기존 동작 유지.
