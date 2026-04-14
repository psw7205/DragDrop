# A1: 컨텐츠 타입 차별화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ShelfContent enum의 `.text`/`.image` case를 실사용하여 이미지 썸네일 + 텍스트 스니펫 미리보기 구현.

**Architecture:** `ShelfStorage`에 UTI 기반 `classifyContent` 메서드를 추가하여 모든 아이템 생성 경로에서 자동 분류. `ShelfItemView`에서 content type별 렌더링 분기.

**Tech Stack:** Swift, SwiftUI, AppKit, UniformTypeIdentifiers, ImageIO (CGImageSource)

**Spec:** `docs/superpowers/specs/2026-04-14-content-type-design.md`

**테스트:** 테스트 타겟 없음. xcodebuild 빌드 검증으로 대체.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `DragDrop/ShelfItem.swift` | Modify | enum case 시그니처 변경 + computed properties |
| `DragDrop/ShelfStorage.swift` | Modify | `classifyContent` 추가, 3개 메서드에서 호출 |
| `DragDrop/ShelfItemView.swift` | Modify | content type별 렌더링 분기 + 썸네일 헬퍼 |

---

### Task 1: ShelfContent enum + ShelfItem 업데이트

**Files:**
- Modify: `DragDrop/ShelfItem.swift`

- [ ] **Step 1: ShelfContent enum case 변경**

현재 (리팩터링에서 정의됨):
```swift
enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)
    case text(string: String, savedURL: URL)
    case image(savedURL: URL, originalName: String?)
}
```

변경:
```swift
enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)
    case text(url: URL, snippet: String)
    case image(url: URL)
}
```

- [ ] **Step 2: ShelfItem computed properties 업데이트**

```swift
var displayName: String {
    switch content {
    case .file(_, let fileName): return fileName
    case .text(let url, _): return url.lastPathComponent
    case .image(let url): return url.lastPathComponent
    }
}

var fileURL: URL {
    switch content {
    case .file(let url, _): return url
    case .text(let url, _): return url
    case .image(let url): return url
    }
}
```

`icon` computed property는 변경 없음.

- [ ] **Step 3: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

빌드 실패 예상 — ShelfStorage에서 기존 `.image(savedURL:, originalName:)` / `.text(string:, savedURL:)` 생성자 사용 중. Task 2에서 수정.

- [ ] **Step 4: Commit (빌드 성공 후 — Task 2와 함께)**

---

### Task 2: ShelfStorage — UTI 기반 분류

**Files:**
- Modify: `DragDrop/ShelfStorage.swift`

- [ ] **Step 1: import 추가**

```swift
import UniformTypeIdentifiers
```

- [ ] **Step 2: classifyContent + readSnippet 메서드 추가**

파일 끝 `isOwnFile` 메서드 뒤에 추가:

```swift
static func classifyContent(url: URL) -> ShelfContent {
    let ext = url.pathExtension
    guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else {
        return .file(url: url, fileName: url.lastPathComponent)
    }

    if type.conforms(to: .image) {
        return .image(url: url)
    }

    if type.conforms(to: .plainText) {
        let snippet = Self.readSnippet(from: url)
        return .text(url: url, snippet: snippet)
    }

    return .file(url: url, fileName: url.lastPathComponent)
}

private static func readSnippet(from url: URL, maxBytes: Int = 512, maxChars: Int = 200) -> String {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: maxBytes) else { return "" }
    let raw = String(decoding: data, as: UTF8.self)
    if raw.count <= maxChars { return raw }
    return String(raw.prefix(maxChars)) + "…"
}
```

- [ ] **Step 3: loadPersistedItems에서 classifyContent 사용**

현재:
```swift
loaded.append(
    ShelfItem(id: uuid, content: .file(url: fileURL, fileName: fileURL.lastPathComponent), addedAt: createdAt)
)
```

변경:
```swift
loaded.append(
    ShelfItem(id: uuid, content: Self.classifyContent(url: fileURL), addedAt: createdAt)
)
```

- [ ] **Step 4: copyFile에서 classifyContent 사용**

현재:
```swift
return ShelfItem(id: id, content: .file(url: destFile, fileName: url.lastPathComponent))
```

변경:
```swift
return ShelfItem(id: id, content: Self.classifyContent(url: destFile))
```

- [ ] **Step 5: saveData에서 classifyContent 사용**

현재:
```swift
return ShelfItem(id: id, content: .file(url: destFile, fileName: fileName))
```

변경:
```swift
return ShelfItem(id: id, content: Self.classifyContent(url: destFile))
```

- [ ] **Step 6: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit (Task 1 + Task 2 함께)**

```bash
git add DragDrop/ShelfItem.swift DragDrop/ShelfStorage.swift
git commit -m "feat: UTI 기반 컨텐츠 타입 분류 — .text/.image case 실사용"
```

---

### Task 3: ShelfItemView — content type별 렌더링

**Files:**
- Modify: `DragDrop/ShelfItemView.swift`

- [ ] **Step 1: import 추가**

```swift
import ImageIO
```

- [ ] **Step 2: 썸네일 생성 헬퍼 추가**

ShelfItemView struct 내부에 private 메서드:

```swift
private func thumbnail(for url: URL, maxSize: CGFloat = 96) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: maxSize,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
```

- [ ] **Step 3: contentPreview ViewBuilder 추가**

기존 body의 아이콘 영역을 `contentPreview`로 대체:

```swift
@ViewBuilder
private var contentPreview: some View {
    switch item.content {
    case .image(let url):
        if let thumb = thumbnail(for: url) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
        }
    case .text(_, let snippet):
        Text(snippet)
            .font(.system(size: 7, design: .monospaced))
            .lineLimit(5)
            .multilineTextAlignment(.leading)
            .padding(4)
            .frame(width: 48, height: 48, alignment: .topLeading)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    case .file:
        Image(nsImage: item.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
    }
}
```

- [ ] **Step 4: body에서 아이콘 영역을 contentPreview로 교체**

기존:
```swift
Image(nsImage: item.icon)
    .resizable()
    .aspectRatio(contentMode: .fit)
    .frame(width: 40, height: 40)
    .frame(width: 48, height: 48)
```

변경:
```swift
contentPreview
    .frame(width: 48, height: 48)
```

- [ ] **Step 5: Build verify**

```bash
cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -project DragDrop.xcodeproj -scheme DragDrop -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add DragDrop/ShelfItemView.swift
git commit -m "feat: 이미지 썸네일 + 텍스트 스니펫 미리보기 렌더링"
```
