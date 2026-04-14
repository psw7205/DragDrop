# A2 링크(URL) 지원 — 설계

## 목표

DragDrop 셸프에 웹 URL을 보관할 수 있도록 링크 컨텐츠 타입을 추가한다.
브라우저 드래그&드롭과 클립보드 붙여넣기 두 경로로 입력받고,
.webloc 파일로 저장하여 macOS 네이티브 호환성을 유지한다.

## 입력 경로

### 브라우저 드래그&드롭

- `ShelfHostingView`에 `.URL` 드래그 타입 등록 (기존 `.fileURL`에 추가)
- `performDragOperation`에서 non-file URL 감지 시 `ShelfViewModel.addLinkAsync(from:)` 호출
- file URL과 web URL을 구분하여 각각 기존 경로 / 신규 경로로 분기

### 클립보드 붙여넣기 (⌘V)

- `ClipboardService.Content`에 `.url(URL)` case 추가
- `read()`에서 텍스트 읽기 전 URL 체크: `URL(string:)` + `scheme`이 http/https인 단일 라인
- `ShelfViewModel.pasteFromClipboard()`에서 `.url` case → `addLinkAsync` 호출

## 데이터 모델

```swift
// ShelfContent — 신규 case
case link(url: URL, originalURL: URL)
// url: 로컬 .webloc 파일 경로
// originalURL: 원본 웹 URL
```

`displayName`: `originalURL.host ?? url.lastPathComponent`
`fileURL`: `url` (로컬 .webloc 파일)

## 저장

`ShelfStorage.saveLink(from originalURL: URL) throws -> ShelfItem`:

1. UUID 디렉토리 생성 (`storageURL/{UUID}/`)
2. .webloc plist 생성: `["URL": originalURL.absoluteString]`
3. 파일명: `{host}.webloc` (host 없으면 `link.webloc`)
4. `ShelfItem` 반환 (content: `.link`)

`classifyContent` 확장:
- `.webloc` 확장자 감지 → plist에서 URL 키 읽기 → `.link(url:originalURL:)` 반환
- plist 파싱 실패 시 `.file`로 폴백

## UI 프리뷰

`ShelfItemView.contentPreview`에 `.link` case 추가:
- SF Symbol `globe` 아이콘 (40×40), `.secondary` 색상
- `displayName`에 도메인명 표시 (예: "github.com")

## 드래그 아웃

기존 `DragSourceView`가 `item.fileURL`(.webloc)을 제공.
대부분 앱에서 .webloc 드래그를 URL로 인식하므로 추가 작업 불필요.

## 변경 파일

| 파일 | 변경 내용 |
|------|----------|
| `ShelfItem.swift` | `.link` case, `displayName`/`fileURL` 분기 |
| `ShelfStorage.swift` | `saveLink()`, `classifyContent` .webloc 처리 |
| `ClipboardService.swift` | `.url(URL)` case, URL 감지 로직 |
| `ShelfHostingView.swift` | `.URL` 드래그 타입 등록, URL 드롭 분기 |
| `ShelfViewModel.swift` | `addLinkAsync(from:)`, `pasteFromClipboard` 분기 |
| `ShelfItemView.swift` | `.link` 프리뷰 렌더링 |

## 변경하지 않는 파일

`DragSourceView`, `GlobalDragMonitor`, `ShelfPanel`, `AppDelegate` — 기존 동작 유지.
