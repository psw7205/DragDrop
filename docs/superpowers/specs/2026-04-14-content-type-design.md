# A1: 컨텐츠 타입 차별화 설계

## 목표

ShelfContent enum의 `.text`/`.image` case를 실사용하여 셸프 아이템을 타입별로 시각 차별화한다.

- 이미지: 실제 썸네일 표시 (파일 아이콘 대신)
- 텍스트: 스니펫 미리보기 (첫 200자)
- 파일: 현행 유지

## 비목표

- 링크(URL) 지원 (A2에서 별도 구현)
- Quick Look 미리보기 (B1에서 별도 구현)
- 설정 UI

## 1. ShelfContent enum 변경

```
enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)       // 현행 유지
    case text(url: URL, snippet: String)        // string → snippet 리네임
    case image(url: URL)                        // originalName 제거
}
```

변경점:
- `.text`: `string` → `snippet` 리네임, `savedURL` → `url` 통일
- `.image`: `originalName` 제거, `savedURL` → `url`

## 2. UTI 기반 분류

`ShelfStorage`에 `classifyContent(url:)` static 메서드 추가.

```
classifyContent(url: URL) → ShelfContent:
  ext = url.pathExtension
  type = UTType(filenameExtension: ext)
  
  if type.conforms(to: .image) → .image(url: url)
  if type.conforms(to: .plainText) → .text(url: url, snippet: readSnippet(url))
  else → .file(url: url, fileName: url.lastPathComponent)
```

분류 기준:
- `.image`: PNG, JPEG, GIF, HEIC, TIFF, WebP, BMP 등 (UTType.image 하위)
- `.plainText`: .txt 등 순수 텍스트 (UTType.plainText 하위). JSON/MD/XML은 .file로 유지.
- `.file`: 그 외 전부

스니펫 생성:
- 파일 앞 512 byte 읽기
- UTF-8 디코딩 (실패 시 .file로 fallback)
- 200자 초과 시 truncate + "…"

## 3. ShelfStorage 변경

`classifyContent`를 모든 아이템 생성 경로에 적용:

- `loadPersistedItems()`: 기존 `.file(url:, fileName:)` → `classifyContent(url:)` 호출
- `copyFile(from:)`: 복사 후 `classifyContent(destFile)` 반환
- `saveData(_:, fileName:)`: 저장 후 `classifyContent(destFile)` 반환

## 4. ShelfItem computed properties 변경

```
displayName:
  .file(_, let fileName) → fileName
  .text(let url, _) → url.lastPathComponent
  .image(let url) → url.lastPathComponent

fileURL:
  .file(let url, _) → url
  .text(let url, _) → url
  .image(let url) → url

icon: 변경 없음 (NSWorkspace 아이콘 — 드래그 이미지용)
```

## 5. ShelfItemView 렌더링 분기

아이콘 영역(48x48)을 content type별로 다르게 렌더링:

### .image
- `CGImageSource`로 96px 썸네일 생성 (효율적 — 전체 이미지 로드 안 함)
- 48x48 프레임에 `.fill` + 4pt cornerRadius clip
- 썸네일 생성 실패 시 NSWorkspace icon으로 fallback

### .text
- 7pt monospaced 폰트, 5줄 lineLimit
- `.leading` 정렬, 4pt 패딩
- `Color.secondary.opacity(0.1)` 배경, 4pt cornerRadius
- 48x48 프레임에 clip

### .file
- 현행 유지 (NSWorkspace icon, 40x40)

파일명 영역(하단): 모든 타입에서 `item.displayName` 표시 (현행 유지).

## 6. 파일 변경 요약

| 파일 | 변경 |
|---|---|
| `ShelfItem.swift` | ShelfContent case 시그니처 변경, computed properties 업데이트 |
| `ShelfStorage.swift` | `classifyContent` 추가, 3개 메서드에서 호출, `import UniformTypeIdentifiers` |
| `ShelfItemView.swift` | content type별 렌더링 분기, 썸네일 헬퍼 |
| `ShelfViewModel.swift` | `saveDataAsync` 변경 불필요 (Storage가 분류 담당) |
