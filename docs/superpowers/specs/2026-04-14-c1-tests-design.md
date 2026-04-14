# C1 테스트 — 설계

## 목표

DragDrop 핵심 비즈니스 로직에 대한 단위 테스트를 추가한다.

## 접근: Swift Package 테스트

프로젝트 루트에 `Package.swift` 추가. 테스트 가능한 소스 파일을 SPM 타겟으로 구성하여 `swift test` 실행.
앱 빌드는 기존 Xcode 프로젝트 유지 (변경 없음).

## Package 구조

```
DragDrop/
├── Package.swift
├── DragDrop/           # 기존 앱 소스 (SPM 타겟으로도 사용)
└── Tests/
    └── DragDropTests/
        ├── ShelfItemTests.swift
        ├── ShelfStorageTests.swift
        ├── ShelfViewModelTests.swift
        └── URLDetectionTests.swift
```

## Package.swift 구성

- 타겟 `DragDropCore`: `DragDrop/` 디렉토리의 소스를 포함하되, AppKit UI 파일은 제외 (SPM에서 컴파일 불가한 파일)
- 문제: `ShelfStorage`, `ShelfViewModel` 등이 AppKit import를 사용하므로 SPM 순수 타겟에서 컴파일 어려움

## 수정된 접근: @testable import 없이 로직만 검증

AppKit 의존이 깊어 SPM 분리가 어려우므로, **Xcode 테스트 타겟을 직접 추가**한다.

1. `DragDropTests` 디렉토리와 테스트 파일 생성
2. `project.pbxproj`에 테스트 타겟 추가
3. `@testable import DragDrop`으로 내부 접근

## 테스트 범위

### ShelfItemTests
- `.file` content → `displayName` = 파일명
- `.text` content → `displayName` = .txt 파일명
- `.image` content → `displayName` = 이미지 파일명
- `.link` content → `displayName` = 도메인명
- 각 content type → `fileURL` 올바른 URL 반환

### ShelfStorageTests
- `classifyContent`: 이미지 확장자 → `.image`
- `classifyContent`: .txt 확장자 → `.text`
- `classifyContent`: .webloc → `.link` (유효한 plist)
- `classifyContent`: .webloc → `.file` (잘못된 plist)
- `classifyContent`: 알 수 없는 확장자 → `.file`
- `saveLink`: .webloc 파일 생성 확인
- `isOwnFile`: storage 내부/외부 경로 구분

### ShelfViewModelTests
- `moveItem`: 정상 이동
- `moveItem`: 동일 위치 → 변경 없음
- `moveItem`: 범위 밖 인덱스 → 클램핑
- `moveItem`: 존재하지 않는 ID → 변경 없음

### URLDetectionTests
- 단일 HTTP URL → `.url` 감지
- 단일 HTTPS URL → `.url` 감지
- 멀티라인 텍스트 → `.text` (URL 아님)
- non-HTTP scheme (ftp://) → `.text`
- 일반 텍스트 → `.text`

## 변경 파일

| 파일 | 변경 |
|------|------|
| `DragDropTests/` (신규) | 테스트 파일 4개 |
| `DragDrop.xcodeproj/project.pbxproj` | 테스트 타겟 추가 |
