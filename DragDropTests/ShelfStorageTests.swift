import XCTest
import UniformTypeIdentifiers
@testable import DragDrop

final class ShelfStorageTests: XCTestCase {
    private var storageRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragDropTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let storageRoot {
            try? FileManager.default.removeItem(at: storageRoot)
        }
        storageRoot = nil
        try super.tearDownWithError()
    }

    private func makeStorage() -> ShelfStorage {
        ShelfStorage(storageURL: storageRoot)
    }

    @discardableResult
    private func createStoredFile(
        id: UUID = UUID(),
        fileName: String = "file.txt",
        size: Int,
        createdAt: Date
    ) throws -> UUID {
        let directory = storageRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0, count: size).write(to: fileURL)
        try FileManager.default.setAttributes([.creationDate: createdAt], ofItemAtPath: fileURL.path)
        return id
    }

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

    func testClassifyText() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "Hello world".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = ShelfStorage.classifyContent(url: tmp)
        if case .text(let u, let snippet) = content {
            XCTAssertEqual(u, tmp)
            XCTAssertEqual(snippet, "Hello world")
        } else {
            XCTFail("Expected .text, got \(content)")
        }
    }

    func testClassifyWebloc() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".webloc")
        let plist: [String: String] = ["URL": "https://example.com"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = ShelfStorage.classifyContent(url: tmp)
        if case .link(let u, let originalURL) = content {
            XCTAssertEqual(u, tmp)
            XCTAssertEqual(originalURL.absoluteString, "https://example.com")
        } else {
            XCTFail("Expected .link, got \(content)")
        }
    }

    func testClassifyInvalidWebloc() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".webloc")
        try "not a plist".write(to: tmp, atomically: true, encoding: .utf8)
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
        let storage = makeStorage()
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
        let storage = makeStorage()
        let fakeInternalURL = storageRoot
            .appendingPathComponent("test-uuid/file.txt")
        XCTAssertTrue(storage.isOwnFile(fakeInternalURL))
    }

    func testIsOwnFileExternal() {
        let storage = makeStorage()
        let externalURL = URL(fileURLWithPath: "/tmp/file.txt")
        XCTAssertFalse(storage.isOwnFile(externalURL))
    }

    // MARK: - Cleanup

    func testStorageMetricsCountsItemsAndBytes() throws {
        let storage = makeStorage()
        let now = Date()
        try createStoredFile(size: 10, createdAt: now)
        try createStoredFile(size: 20, createdAt: now)

        let metrics = try storage.storageMetrics()

        XCTAssertEqual(metrics.itemCount, 2)
        XCTAssertEqual(metrics.totalBytes, 30)
    }

    func testStorageMetricsCountsNestedDirectoryFileBytesRecursively() throws {
        let storage = makeStorage()
        let id = UUID()
        let itemDirectory = storageRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let folderURL = itemDirectory.appendingPathComponent("Folder", isDirectory: true)
        let nestedURL = folderURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10).write(to: folderURL.appendingPathComponent("root.txt"))
        try Data(repeating: 0, count: 20).write(to: nestedURL.appendingPathComponent("nested.txt"))

        let metrics = try storage.storageMetrics()

        XCTAssertEqual(metrics.itemCount, 1)
        XCTAssertEqual(metrics.totalBytes, 30)
    }

    func testCleanupRemovesItemsOlderThanMaximumAge() throws {
        let storage = makeStorage()
        let now = Date()
        let oldID = try createStoredFile(size: 10, createdAt: now.addingTimeInterval(-120))
        let freshID = try createStoredFile(size: 10, createdAt: now.addingTimeInterval(-30))

        let result = try storage.cleanup(using: ShelfCleanupPolicy(maximumAge: 60), now: now)

        XCTAssertEqual(result.removedItemIDs, [oldID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(oldID.uuidString).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(freshID.uuidString).path))
    }

    func testCleanupRemovesOldestItemsUntilTotalSizeIsUnderLimit() throws {
        let storage = makeStorage()
        let now = Date()
        let oldestID = try createStoredFile(size: 80, createdAt: now.addingTimeInterval(-300))
        let middleID = try createStoredFile(size: 40, createdAt: now.addingTimeInterval(-200))
        let newestID = try createStoredFile(size: 20, createdAt: now.addingTimeInterval(-100))

        let result = try storage.cleanup(using: ShelfCleanupPolicy(maximumTotalBytes: 60), now: now)

        XCTAssertEqual(result.removedItemIDs, [oldestID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(oldestID.uuidString).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(middleID.uuidString).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent(newestID.uuidString).path))
        XCTAssertEqual(try storage.storageMetrics().totalBytes, 60)
    }
}
