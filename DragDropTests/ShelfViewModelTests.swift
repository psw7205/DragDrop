import XCTest
@testable import DragDrop

final class ShelfViewModelTests: XCTestCase {

    private func makeViewModel(with items: [ShelfItem]) -> ShelfViewModel {
        let vm = ShelfViewModel()
        // items를 직접 설정할 수 없으므로 (storage에서 로드), 테스트용으로 접근
        vm.items = items
        return vm
    }

    private func makeItem(fileName: String = "test.txt") -> ShelfItem {
        ShelfItem(content: .file(url: URL(fileURLWithPath: "/tmp/\(fileName)"), fileName: fileName))
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
}
