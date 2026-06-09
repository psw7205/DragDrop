# Settings Configurable Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`로 이 계획을 task 단위로 실행한다. 진행 추적은 checkbox(`- [ ]`)를 사용한다.

**Goal:** 기존 기본 cleanup 동작(`30 days + 1 GB`)을 유지하면서, 사용자가 `Preferences...` 창에서 보관 기간과 저장소 한도를 설정할 수 있게 한다.

**Architecture:** cleanup 실행은 기존 `ShelfViewModel.cleanupStorage(using:)` 경로를 유지한다. `UserDefaults` 기반 `ShelfPreferences`가 UI 선택값을 `ShelfCleanupPolicy`로 변환하고, `AppDelegate`는 status menu, preferences window, `Launch at Login`, cleanup 실행 같은 AppKit boundary를 담당한다.

**Tech Stack:** Swift 5, SwiftUI, AppKit, ServiceManagement, XCTest, Xcode file-system synchronized groups.

---

## 성공 기준

- 기본 설정은 `ShelfCleanupPolicy.manualStorageCleanup`과 동일한 `30 days + 1 GB` 정책을 만든다.
- `Storage retention = Forever`는 age 기준 삭제를 비활성화한다.
- `Storage size limit = Off`는 용량 기준 삭제를 비활성화한다.
- custom retention/size 값은 저장 전에 안전 범위로 clamp된다.
- status menu에 `Preferences...` 항목이 추가된다.
- Preferences 창에는 `Launch at Login`, retention, size limit, 현재 item count/total size, `Clean Now`가 있다.
- 기존 `Clean Up Storage...`는 설정된 policy와 policy-aware 확인 문구를 사용한다.
- `Clean Now`는 cleanup 후 shelf state와 storage metrics를 갱신한다.
- 전체 test와 Debug build가 통과한다.

## 변경 파일

- Create: `DragDrop/ShelfPreferences.swift`
  - `ShelfRetentionOption`, `ShelfSizeLimitOption`, `ShelfPreferences` 정의
  - `UserDefaults` persistence, custom 값 validation, `ShelfCleanupPolicy` 변환, cleanup 설명 문구 담당
- Create: `DragDrop/PreferencesView.swift`
  - SwiftUI preferences UI
  - storage metrics, cleanup, `Launch at Login` 변경은 closure로 위임
- Create: `DragDropTests/ShelfPreferencesTests.swift`
  - 기본 policy, disabled criteria, custom clamp, persistence 검증
- Modify: `DragDrop/ShelfViewModel.swift`
  - `storageMetrics()` forwarding method 추가
- Modify: `DragDrop/AppDelegate.swift`
  - `ShelfPreferences` 보유, `Preferences...` menu item, preferences window, configured cleanup wiring 추가
- Modify: `DragDropTests/ShelfViewModelTests.swift`
  - view model metrics forwarding 검증

## Task 1: Preferences Model

- [x] `DragDropTests/ShelfPreferencesTests.swift`를 먼저 추가한다.
- [x] `xcodebuild test -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug -destination 'platform=macOS' -only-testing:DragDropTests/ShelfPreferencesTests`를 실행해 `ShelfPreferences` 타입 부재로 RED를 확인한다.
- [x] `DragDrop/ShelfPreferences.swift`를 추가한다.
- [x] 같은 targeted test를 다시 실행해 GREEN을 확인한다.

## Task 2: ViewModel Metrics Boundary

- [x] `ShelfViewModelTests.testStorageMetricsReturnsCurrentStorageMetrics`를 먼저 추가한다.
- [x] targeted test를 실행해 `ShelfViewModel.storageMetrics()` 부재로 RED를 확인한다.
- [x] `ShelfViewModel.storageMetrics()`를 추가한다.
- [x] targeted test를 다시 실행해 GREEN을 확인한다.

## Task 3: Preferences UI And AppDelegate Wiring

- [x] `PreferencesView`를 추가한다.
  - `Launch at Login` toggle
  - `Storage retention` picker: `1 Day`, `7 Days`, `30 Days`, `Forever`, `Custom`
  - custom days stepper
  - `Storage size limit` picker: `Off`, `512 MB`, `1 GB`, `Custom`
  - custom MB stepper
  - current storage metrics
  - `Refresh`, `Clean Now`
- [x] `AppDelegate`에서 `Preferences...` menu item과 preferences window lifecycle을 연결한다.
- [x] 기존 `Clean Up Storage...`와 preferences `Clean Now`가 `preferences.cleanupPolicy`를 사용하도록 연결한다.
- [x] `xcodebuild build -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug -destination 'platform=macOS'`로 compile 검증한다.

## Task 4: Full Verification

- [x] 전체 테스트 실행:

```bash
xcodebuild test -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug -destination 'platform=macOS'
```

- [x] Debug build 실행:

```bash
xcodebuild build -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug -destination 'platform=macOS'
```

- [x] `git status --short --branch`와 diff를 확인해 변경 범위가 `Settings + configurable cleanup`에 묶여 있는지 확인한다.
