# A2 링크(URL) 지원 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DragDrop 셸프에 웹 URL을 보관할 수 있도록 링크 컨텐츠 타입을 추가한다.

**Architecture:** `ShelfContent.link` case 추가 → .webloc 파일로 저장 → 브라우저 드래그&드롭 + 클립보드 붙여넣기 두 경로로 입력 → globe 아이콘 + 도메인명 프리뷰 렌더링.

**Tech Stack:** Swift, SwiftUI, AppKit (NSPasteboard, NSDraggingInfo), UniformTypeIdentifiers, PropertyListSerialization

**Spec:** `docs/superpowers/specs/2026-04-14-a2-link-support-design.md`

**테스트 타겟 없음** — 빌드 검증 + 수동 테스트로 확인.

---

### Task 1: ShelfContent.link case + ShelfItem 확장

**Files:**
- Modify: `DragDrop/ShelfItem.swift:4-8` (ShelfContent enum)
- Modify: `DragDrop/ShelfItem.swift:16-29` (displayName, fileURL 분기)

- [ ] **Step 1: ShelfContent에 .link case 추가**

`DragDrop/ShelfItem.swift` — enum에 case 추가:

```swift
enum ShelfContent: Equatable {
    case file(url: URL, fileName: String)
    case text(url: URL, snippet: String)
    case image(url: URL)
    case link(url: URL, originalURL: URL)
}
```

- [ ] **Step 2: displayName에 .link 분기 추가**

`ShelfItem.displayName` computed property:

```swift
var displayName: String {
    switch content {
    case .file(_, let fileName): return fileName
    case .text(let url, _): return url.lastPathComponent
    case .image(let url): return url.lastPathComponent
    case .link(_, let originalURL): return originalURL.host ?? "link"
    }
}
```

- [ ] **Step 3: fileURL에 .link 분기 추가**

`ShelfItem.fileURL` computed property:

```swift
var fileURL: URL {
    switch content {
    case .file(let url, _): return url
    case .text(let url, _): return url
    case .image(let url): return url
    case .link(let url, _): return url
    }
}
```

- [ ] **Step 4: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: 커밋**

```bash
git add DragDrop/ShelfItem.swift
git commit -m "feat(a2): ShelfContent.link case 추가"
```

---

### Task 2: ShelfStorage — saveLink + classifyContent .webloc 처리

**Files:**
- Modify: `DragDrop/ShelfStorage.swift:124-139` (classifyContent)
- Modify: `DragDrop/ShelfStorage.swift` (saveLink 메서드 추가)

- [ ] **Step 1: saveLink 메서드 추가**

`DragDrop/ShelfStorage.swift` — `saveData` 메서드 뒤(L47 이후)에 추가:

```swift
func saveLink(from originalURL: URL) throws -> ShelfItem {
    let id = UUID()
    let destDir = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
    let host = originalURL.host ?? "link"
    let destFile = destDir.appendingPathComponent("\(host).webloc")

    do {
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let plist: [String: String] = ["URL": originalURL.absoluteString]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: destFile)
        return ShelfItem(id: id, content: .link(url: destFile, originalURL: originalURL))
    } catch {
        try? FileManager.default.removeItem(at: destDir)
        throw error
    }
}
```

- [ ] **Step 2: classifyContent에 .webloc 분기 추가**

`DragDrop/ShelfStorage.swift` `classifyContent` 메서드 — image 체크 전에 .webloc 분기 삽입:

```swift
static func classifyContent(url: URL) -> ShelfContent {
    let ext = url.pathExtension
    guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else {
        return .file(url: url, fileName: url.lastPathComponent)
    }

    if ext.lowercased() == "webloc", let originalURL = readWeblocURL(from: url) {
        return .link(url: url, originalURL: originalURL)
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
```

- [ ] **Step 3: readWeblocURL 헬퍼 추가**

`DragDrop/ShelfStorage.swift` — `readSnippet` 메서드 뒤에 추가:

```swift
private static func readWeblocURL(from url: URL) -> URL? {
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let urlString = plist["URL"] as? String,
          let originalURL = URL(string: urlString) else {
        return nil
    }
    return originalURL
}
```

- [ ] **Step 4: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: 커밋**

```bash
git add DragDrop/ShelfStorage.swift
git commit -m "feat(a2): saveLink + .webloc classifyContent 처리"
```

---

### Task 3: ClipboardService — URL 감지

**Files:**
- Modify: `DragDrop/ClipboardService.swift:4-8` (Content enum)
- Modify: `DragDrop/ClipboardService.swift:10-33` (read 메서드)

- [ ] **Step 1: Content enum에 .url case 추가**

```swift
enum Content {
    case files([URL])
    case image(Data, suggestedName: String)
    case text(String, suggestedName: String)
    case url(URL)
}
```

- [ ] **Step 2: read()에 URL 감지 로직 추가**

`read()` 메서드 — 기존 텍스트 체크(`pasteboard.string(forType: .string)`) 부분을 URL 체크 포함으로 교체:

```swift
if let text = pasteboard.string(forType: .string), !text.isEmpty {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.contains("\n"),
       let parsedURL = URL(string: trimmed),
       let scheme = parsedURL.scheme,
       ["http", "https"].contains(scheme.lowercased()) {
        return .url(parsedURL)
    }
    return .text(text, suggestedName: "Clipboard \(timestamp).txt")
}
```

- [ ] **Step 3: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 커밋**

```bash
git add DragDrop/ClipboardService.swift
git commit -m "feat(a2): ClipboardService URL 감지"
```

---

### Task 4: ShelfViewModel — URL 입력 경로 연결

**Files:**
- Modify: `DragDrop/ShelfViewModel.swift:131-142` (pasteFromClipboard)
- Modify: `DragDrop/ShelfViewModel.swift` (addLinkAsync 추가)

- [ ] **Step 1: addLinkAsync 메서드 추가**

`DragDrop/ShelfViewModel.swift` — `addFilesAsync` 메서드 뒤(L83 이후)에 추가:

```swift
func addLinkAsync(from url: URL) {
    isManuallyHidden = false
    pendingAddCount += 1

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        do {
            let item = try self.storage.saveLink(from: url)
            DispatchQueue.main.async {
                self.items.append(item)
                self.pendingAddCount -= 1
            }
        } catch {
            DispatchQueue.main.async {
                self.lastErrorMessage = "링크 추가 실패: \(error.localizedDescription)"
                self.pendingAddCount -= 1
            }
        }
    }
}
```

- [ ] **Step 2: pasteFromClipboard에 .url case 추가**

```swift
func pasteFromClipboard() {
    guard let content = clipboard.read() else { return }
    switch content {
    case .files(let urls):
        addFilesAsync(from: urls)
    case .url(let url):
        addLinkAsync(from: url)
    case .image(let data, let name):
        saveDataAsync(data, fileName: name)
    case .text(let text, let name):
        guard let data = text.data(using: .utf8) else { return }
        saveDataAsync(data, fileName: name)
    }
}
```

- [ ] **Step 3: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 커밋**

```bash
git add DragDrop/ShelfViewModel.swift
git commit -m "feat(a2): ViewModel addLinkAsync + paste 분기"
```

---

### Task 5: ShelfHostingView — URL 드래그 타입 지원

**Files:**
- Modify: `DragDrop/ShelfHostingView.swift:4-7` (콜백 프로퍼티)
- Modify: `DragDrop/ShelfHostingView.swift:20` (registerForDraggedTypes)
- Modify: `DragDrop/ShelfHostingView.swift:39-48` (performDragOperation)

- [ ] **Step 1: onLinkDropped 콜백 + 드래그 타입 등록**

`ShelfHostingView` 프로퍼티에 추가:

```swift
var onLinkDropped: ((URL) -> Void)?
```

`registerForDraggedTypes` 수정:

```swift
registerForDraggedTypes([.fileURL, .URL])
```

- [ ] **Step 2: performDragOperation에서 URL 드롭 분기**

```swift
override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let pasteboard = sender.draggingPasteboard

    // file URL 먼저 시도
    if let fileURLs = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL], !fileURLs.isEmpty {
        onFilesDropped?(fileURLs)
        return true
    }

    // non-file URL (웹 링크)
    if let urls = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: false]
    ) as? [URL], let webURL = urls.first,
       let scheme = webURL.scheme, ["http", "https"].contains(scheme.lowercased()) {
        onLinkDropped?(webURL)
        return true
    }

    return false
}
```

- [ ] **Step 3: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 커밋**

```bash
git add DragDrop/ShelfHostingView.swift
git commit -m "feat(a2): ShelfHostingView URL 드래그 타입 지원"
```

---

### Task 6: AppDelegate — onLinkDropped 콜백 연결

**Files:**
- Modify: `DragDrop/AppDelegate.swift:34-38` (setupPanel 내 hostingView 콜백 설정)

- [ ] **Step 1: onLinkDropped 콜백 연결**

`DragDrop/AppDelegate.swift` `setupPanel()` — 기존 `onFilesDropped` 블록(L34-38) 뒤에 추가:

```swift
hostingView.onLinkDropped = { [weak self] url in
    self?.viewModel.addLinkAsync(from: url)
    self?.viewModel.isDragHovering = false
    self?.viewModel.isExternalDragging = false
}
```

- [ ] **Step 2: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: 커밋**

```bash
git add DragDrop/AppDelegate.swift
git commit -m "feat(a2): AppDelegate onLinkDropped 연결"
```

---

### Task 7: ShelfItemView — 링크 프리뷰 렌더링

**Files:**
- Modify: `DragDrop/ShelfItemView.swift:23-53` (contentPreview)

- [ ] **Step 1: contentPreview에 .link case 추가**

`ShelfItemView`의 `contentPreview` — `.text` case 뒤에 `.link` 추가:

```swift
case .link:
    Image(systemName: "globe")
        .font(.system(size: 28))
        .foregroundStyle(.secondary)
        .frame(width: 48, height: 48)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
```

- [ ] **Step 2: 빌드 검증**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: 커밋**

```bash
git add DragDrop/ShelfItemView.swift
git commit -m "feat(a2): 링크 프리뷰 globe 아이콘 렌더링"
```

---

### Task 8: 통합 빌드 검증 + 수동 테스트

- [ ] **Step 1: 클린 빌드**

Run: `cd /Users/hc/Repository/etc/dragdrop/DragDrop && xcodebuild -scheme DragDrop -configuration Debug clean build 2>&1 | tail -5`
Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: 수동 테스트 체크리스트**

앱 실행 후 확인:
1. 브라우저에서 URL을 셸프로 드래그 → globe 아이콘 + 도메인명 표시
2. `https://github.com` 복사 후 ⌘V → 링크 아이템 추가됨
3. 일반 텍스트 복사 후 ⌘V → 기존 텍스트 처리 유지
4. 셸프의 링크 아이템을 외부 드래그 → .webloc 전달
5. 앱 재시작 → 링크 아이템 영속성 확인
6. 파일 드래그&드롭 → 기존 동작 정상

- [ ] **Step 3: 최종 커밋 (필요 시)**

수동 테스트에서 발견된 문제 수정 후 커밋.
