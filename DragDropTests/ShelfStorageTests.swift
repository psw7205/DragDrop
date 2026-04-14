import XCTest
import UniformTypeIdentifiers
@testable import DragDrop

final class ShelfStorageTests: XCTestCase {

    // MARK: - classifyContent

    func testClassifyImage() {
        let url = URL(fileURLWithPath: "/tmp/photo.png")
        let content = ShelfStorage.classifyContent(url: url)
        if case .image(let u) = content {
            XCTAssertEqual(u, url)
        } else {
            XCTFail("Expected .image, got \(content)")
        }
    }

    func testClassifyJPEG() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        let content = ShelfStorage.classifyContent(url: url)
        if case .image = content {} else {
            XCTFail("Expected .image, got \(content)")
        }
    }

    func testClassifyText() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try! "Hello world".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = ShelfStorage.classifyContent(url: tmp)
        if case .text(let u, let snippet) = content {
            XCTAssertEqual(u, tmp)
            XCTAssertEqual(snippet, "Hello world")
        } else {
            XCTFail("Expected .text, got \(content)")
        }
    }

    func testClassifyWebloc() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".webloc")
        let plist: [String: String] = ["URL": "https://example.com"]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try! data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = ShelfStorage.classifyContent(url: tmp)
        if case .link(let u, let originalURL) = content {
            XCTAssertEqual(u, tmp)
            XCTAssertEqual(originalURL.absoluteString, "https://example.com")
        } else {
            XCTFail("Expected .link, got \(content)")
        }
    }

    func testClassifyInvalidWebloc() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".webloc")
        try! "not a plist".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = ShelfStorage.classifyContent(url: tmp)
        if case .file(_, let fileName) = content {
            XCTAssertTrue(fileName.hasSuffix(".webloc"))
        } else {
            XCTFail("Expected .file fallback, got \(content)")
        }
    }

    func testClassifyUnknownExtension() {
        let url = URL(fileURLWithPath: "/tmp/data.xyz")
        let content = ShelfStorage.classifyContent(url: url)
        if case .file(_, let fileName) = content {
            XCTAssertEqual(fileName, "data.xyz")
        } else {
            XCTFail("Expected .file, got \(content)")
        }
    }

    // MARK: - saveLink

    func testSaveLink() throws {
        let storage = ShelfStorage()
        let url = URL(string: "https://github.com/test")!
        let item = try storage.saveLink(from: url)

        if case .link(let savedURL, let originalURL) = item.content {
            XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
            XCTAssertEqual(originalURL, url)
            XCTAssertTrue(savedURL.lastPathComponent.hasSuffix(".webloc"))
        } else {
            XCTFail("Expected .link content")
        }

        // cleanup
        storage.removeItem(item)
    }

    // MARK: - isOwnFile

    func testIsOwnFileInStorage() {
        let storage = ShelfStorage()
        let fakeInternalURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DragDrop/Items/test-uuid/file.txt")
        XCTAssertTrue(storage.isOwnFile(fakeInternalURL))
    }

    func testIsOwnFileExternal() {
        let storage = ShelfStorage()
        let externalURL = URL(fileURLWithPath: "/tmp/file.txt")
        XCTAssertFalse(storage.isOwnFile(externalURL))
    }
}
