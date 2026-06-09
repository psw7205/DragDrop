import AppKit
import XCTest
@testable import DragDrop

final class DragSourceViewTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragSourceViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testShelfDragPasteboardWriterExposesFileURLAndShelfIDsOnSameItem() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DragSourceViewTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }

        let url = makeTempFile(named: "photo.png")
        let ids = [UUID(), UUID()]
        let writer = ShelfDragPasteboardWriter(fileURL: url, shelfItemIDs: ids)

        XCTAssertTrue(pasteboard.writeObjects([writer]))

        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(urls, [url])
        XCTAssertEqual(
            pasteboard.string(forType: .shelfItemIDs),
            ids.map(\.uuidString).joined(separator: "\n")
        )
    }

    func testShelfDragPasteboardWriterCanOmitShelfIDsForAdditionalFileItems() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DragSourceViewTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }

        let urls = [
            makeTempFile(named: "one.png"),
            makeTempFile(named: "two.png"),
        ]
        let writers = [
            ShelfDragPasteboardWriter(fileURL: urls[0], shelfItemIDs: [UUID()]),
            ShelfDragPasteboardWriter(fileURL: urls[1], shelfItemIDs: []),
        ]

        XCTAssertTrue(pasteboard.writeObjects(writers))

        let pastedURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(pastedURLs, urls)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, urls.count)
    }

    private func makeTempFile(named fileName: String) -> URL {
        let url = tempDirectory.appendingPathComponent(fileName)
        _ = FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        return url
    }
}
