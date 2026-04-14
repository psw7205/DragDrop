import XCTest
@testable import DragDrop

final class ShelfItemTests: XCTestCase {

    func testFileDisplayName() {
        let item = ShelfItem(content: .file(url: URL(fileURLWithPath: "/tmp/doc.pdf"), fileName: "doc.pdf"))
        XCTAssertEqual(item.displayName, "doc.pdf")
    }

    func testTextDisplayName() {
        let url = URL(fileURLWithPath: "/tmp/note.txt")
        let item = ShelfItem(content: .text(url: url, snippet: "hello"))
        XCTAssertEqual(item.displayName, "note.txt")
    }

    func testImageDisplayName() {
        let url = URL(fileURLWithPath: "/tmp/photo.png")
        let item = ShelfItem(content: .image(url: url))
        XCTAssertEqual(item.displayName, "photo.png")
    }

    func testLinkDisplayName() {
        let saved = URL(fileURLWithPath: "/tmp/github.com.webloc")
        let original = URL(string: "https://github.com/repo")!
        let item = ShelfItem(content: .link(url: saved, originalURL: original))
        XCTAssertEqual(item.displayName, "github.com")
    }

    func testLinkDisplayNameWithoutHost() {
        let saved = URL(fileURLWithPath: "/tmp/link.webloc")
        let original = URL(string: "https:///path")!
        let item = ShelfItem(content: .link(url: saved, originalURL: original))
        XCTAssertEqual(item.displayName, "link")
    }

    func testFileURL() {
        let url = URL(fileURLWithPath: "/tmp/doc.pdf")
        let item = ShelfItem(content: .file(url: url, fileName: "doc.pdf"))
        XCTAssertEqual(item.fileURL, url)
    }

    func testLinkFileURL() {
        let saved = URL(fileURLWithPath: "/tmp/github.com.webloc")
        let original = URL(string: "https://github.com")!
        let item = ShelfItem(content: .link(url: saved, originalURL: original))
        XCTAssertEqual(item.fileURL, saved)
    }
}
