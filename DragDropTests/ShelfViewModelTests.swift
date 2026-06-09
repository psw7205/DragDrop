import XCTest
@testable import DragDrop

final class ShelfViewModelTests: XCTestCase {
    private var storageRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragDropViewModelTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeViewModel(with items: [ShelfItem], storage: ShelfStorage? = nil) -> ShelfViewModel {
        let vm = ShelfViewModel(storage: storage ?? makeStorage())
        vm.items = items
        return vm
    }

    private func makeItem(fileName: String = "test.txt", addedAt: Date = Date()) -> ShelfItem {
        ShelfItem(
            content: .file(url: URL(fileURLWithPath: "/tmp/\(fileName)"), fileName: fileName),
            addedAt: addedAt
        )
    }

    private func makeLinkItem(host: String, path: String = "/docs", addedAt: Date = Date()) -> ShelfItem {
        let savedURL = URL(fileURLWithPath: "/tmp/\(host).webloc")
        let originalURL = URL(string: "https://\(host)\(path)")!
        return ShelfItem(content: .link(url: savedURL, originalURL: originalURL), addedAt: addedAt)
    }

    private func createStoredItem(
        id: UUID = UUID(),
        fileName: String = "file.txt",
        size: Int,
        createdAt: Date
    ) throws -> ShelfItem {
        let directory = storageRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0, count: size).write(to: fileURL)
        try FileManager.default.setAttributes([.creationDate: createdAt], ofItemAtPath: fileURL.path)
        return ShelfItem(id: id, content: .file(url: fileURL, fileName: fileName), addedAt: createdAt)
    }

    // MARK: - displayState

    func testDisplayStateKeepsItemsExpandedDuringExternalDrag() {
        let vm = makeViewModel(with: [makeItem()])

        vm.isExternalDragging = true

        XCTAssertEqual(vm.displayState, .expanded)
    }

    func testDisplayStateShowsIndicatorForExternalDragWhenEmpty() {
        let vm = makeViewModel(with: [])

        vm.isExternalDragging = true

        XCTAssertEqual(vm.displayState, .indicator)
    }

    // MARK: - cleanupStorage

    func testCleanupStorageRemovesDeletedItemsFromMemoryAndSelection() throws {
        let storage = makeStorage()
        let now = Date()
        let oldItem = try createStoredItem(size: 10, createdAt: now.addingTimeInterval(-120))
        let freshItem = try createStoredItem(size: 10, createdAt: now.addingTimeInterval(-30))
        let vm = makeViewModel(with: [oldItem, freshItem], storage: storage)
        vm.selectedIDs = [oldItem.id, freshItem.id]

        let result = try vm.cleanupStorage(using: ShelfCleanupPolicy(maximumAge: 60), now: now)

        XCTAssertEqual(result.removedItemIDs, [oldItem.id])
        XCTAssertEqual(vm.items.map(\.id), [freshItem.id])
        XCTAssertEqual(vm.selectedIDs, [freshItem.id])
    }

    func testStorageMetricsReturnsCurrentStorageMetrics() throws {
        let storage = makeStorage()
        let now = Date()
        let firstItem = try createStoredItem(size: 10, createdAt: now)
        let secondItem = try createStoredItem(size: 20, createdAt: now)
        let vm = makeViewModel(with: [firstItem, secondItem], storage: storage)

        let metrics = try vm.storageMetrics()

        XCTAssertEqual(metrics.itemCount, 2)
        XCTAssertEqual(metrics.totalBytes, 30)
    }

    // MARK: - context menu

    func testContextMenuItemsSelectsUnselectedTargetOnly() {
        let items = (0..<3).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        vm.selectedIDs = [items[0].id, items[1].id]

        let contextItems = vm.contextMenuItems(for: items[2].id)

        XCTAssertEqual(contextItems.map(\.id), [items[2].id])
        XCTAssertEqual(vm.selectedIDs, [items[2].id])
    }

    func testContextMenuItemsPreservesSelectedSetForSelectedTarget() {
        let items = (0..<4).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        vm.selectedIDs = [items[1].id, items[3].id]

        let contextItems = vm.contextMenuItems(for: items[3].id)

        XCTAssertEqual(contextItems.map(\.id), [items[1].id, items[3].id])
        XCTAssertEqual(vm.selectedIDs, [items[1].id, items[3].id])
    }

    func testContextMenuItemsIgnoresUnknownTarget() {
        let items = (0..<2).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        vm.selectedIDs = [items[0].id]

        let contextItems = vm.contextMenuItems(for: UUID())

        XCTAssertTrue(contextItems.isEmpty)
        XCTAssertEqual(vm.selectedIDs, [items[0].id])
    }

    // MARK: - drag payload

    func testDragItemsUsesSelectedItemsWhenSourceIsSelected() {
        let items = (0..<4).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        vm.selectedIDs = [items[1].id, items[3].id]

        let dragItems = vm.dragItems(for: items[3].id)

        XCTAssertEqual(dragItems.map(\.id), [items[1].id, items[3].id])
    }

    func testDragItemsUsesOnlySourceWhenSourceIsNotSelected() {
        let items = (0..<4).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        vm.selectedIDs = [items[0].id, items[1].id]

        let dragItems = vm.dragItems(for: items[3].id)

        XCTAssertEqual(dragItems.map(\.id), [items[3].id])
    }

    // MARK: - search and sort

    func testVisibleItemsFiltersByNameWithoutChangingManualOrder() {
        let items = [
            makeItem(fileName: "Invoice.pdf"),
            makeItem(fileName: "Meeting Notes.txt"),
            makeItem(fileName: "Invoice.png"),
        ]
        let vm = makeViewModel(with: items)

        vm.query = "invoice"

        XCTAssertEqual(vm.visibleItems.map(\.id), [items[0].id, items[2].id])
        XCTAssertEqual(vm.items.map(\.id), items.map(\.id))
    }

    func testVisibleItemsSearchesLinkHost() {
        let file = makeItem(fileName: "report.pdf")
        let link = makeLinkItem(host: "developer.apple.com")
        let vm = makeViewModel(with: [file, link])

        vm.query = "apple"

        XCTAssertEqual(vm.visibleItems.map(\.id), [link.id])
    }

    func testVisibleItemsSortsByName() {
        let items = [
            makeItem(fileName: "zeta.txt"),
            makeItem(fileName: "Alpha.txt"),
            makeItem(fileName: "middle.txt"),
        ]
        let vm = makeViewModel(with: items)

        vm.sortMode = .name

        XCTAssertEqual(vm.visibleItems.map(\.displayName), ["Alpha.txt", "middle.txt", "zeta.txt"])
        XCTAssertEqual(vm.items.map(\.id), items.map(\.id))
    }

    func testVisibleItemsSortsByAddedNewestFirst() {
        let now = Date()
        let old = makeItem(fileName: "old.txt", addedAt: now.addingTimeInterval(-120))
        let fresh = makeItem(fileName: "fresh.txt", addedAt: now)
        let middle = makeItem(fileName: "middle.txt", addedAt: now.addingTimeInterval(-60))
        let vm = makeViewModel(with: [old, fresh, middle])

        vm.sortMode = .added

        XCTAssertEqual(vm.visibleItems.map(\.id), [fresh.id, middle.id, old.id])
    }

    func testVisibleItemsSortsBySizeDescending() throws {
        let now = Date()
        let small = try createStoredItem(fileName: "small.txt", size: 8, createdAt: now)
        let large = try createStoredItem(fileName: "large.txt", size: 32, createdAt: now)
        let medium = try createStoredItem(fileName: "medium.txt", size: 16, createdAt: now)
        let vm = makeViewModel(with: [small, large, medium])

        vm.sortMode = .size

        XCTAssertEqual(vm.visibleItems.map(\.id), [large.id, medium.id, small.id])
    }

    func testMoveItemIgnoredOutsideManualSortMode() {
        let items = (0..<3).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        vm.sortMode = .name

        vm.moveItem(withID: items[0].id, toIndex: 2)

        XCTAssertEqual(vm.items.map(\.id), items.map(\.id))
    }

    func testMoveItemIgnoredWhileSearchIsActive() {
        let items = (0..<3).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        vm.query = "file"

        vm.moveItem(withID: items[0].id, toIndex: 2)

        XCTAssertEqual(vm.items.map(\.id), items.map(\.id))
    }

    func testMetadataIncludesReadableSizeKindAndLinkHost() {
        let link = makeLinkItem(host: "example.com")
        let vm = makeViewModel(with: [link])

        let metadata = vm.metadata(for: link)

        XCTAssertEqual(metadata.kind, "Link")
        XCTAssertEqual(metadata.sizeBytes, 0)
        XCTAssertTrue(metadata.searchText.contains("example.com"))
        XCTAssertTrue(metadata.tooltipText.contains("example.com"))
    }

    // MARK: - moveItem

    func testMoveItemForward() {
        let items = (0..<4).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        let targetID = items[0].id

        vm.moveItem(withID: targetID, toIndex: 2)

        XCTAssertEqual(vm.items[2].id, targetID)
    }

    func testMoveItemBackward() {
        let items = (0..<4).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        let targetID = items[3].id

        vm.moveItem(withID: targetID, toIndex: 1)

        XCTAssertEqual(vm.items[1].id, targetID)
    }

    func testMoveItemSamePosition() {
        let items = (0..<4).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        let originalOrder = vm.items.map(\.id)

        vm.moveItem(withID: items[2].id, toIndex: 2)

        XCTAssertEqual(vm.items.map(\.id), originalOrder)
    }

    func testMoveItemClampsTooLargeIndex() {
        let items = (0..<3).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        let targetID = items[0].id

        vm.moveItem(withID: targetID, toIndex: 100)

        XCTAssertEqual(vm.items.last?.id, targetID)
    }

    func testMoveItemClampsNegativeIndex() {
        let items = (0..<3).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        let targetID = items[2].id

        vm.moveItem(withID: targetID, toIndex: -5)

        XCTAssertEqual(vm.items.first?.id, targetID)
    }

    func testMoveItemUnknownID() {
        let items = (0..<3).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)
        let originalOrder = vm.items.map(\.id)

        vm.moveItem(withID: UUID(), toIndex: 0)

        XCTAssertEqual(vm.items.map(\.id), originalOrder)
    }

    func testMoveItemsPreservesSelectedGroupOrder() {
        let items = (0..<5).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)

        vm.moveItems(withIDs: [items[1].id, items[3].id], toIndex: 4)

        XCTAssertEqual(
            vm.items.map(\.id),
            [items[0].id, items[2].id, items[4].id, items[1].id, items[3].id]
        )
    }

    func testMoveItemsIgnoresUnknownIDsAndKeepsKnownGroup() {
        let items = (0..<4).map { makeItem(fileName: "file\($0).txt") }
        let vm = makeViewModel(with: items)

        vm.moveItems(withIDs: [UUID(), items[0].id, items[2].id], toIndex: 1)

        XCTAssertEqual(
            vm.items.map(\.id),
            [items[1].id, items[0].id, items[2].id, items[3].id]
        )
    }
}
