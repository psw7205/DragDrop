import AppKit
import Carbon.HIToolbox
import XCTest
@testable import DragDrop

final class GlobalDragMonitorTests: XCTestCase {
    func testToggleShelfHotKeyUsesCarbonOptionShiftDDescriptor() {
        XCTAssertEqual(ShelfHotKey.toggleShelf.keyCode, UInt32(kVK_ANSI_D))
        XCTAssertEqual(ShelfHotKey.toggleShelf.carbonModifiers, UInt32(optionKey | shiftKey))
    }

    func testCarbonHotKeyMonitorRegistersOnlyOnceAndStopsRegisteredShortcut() throws {
        var registeredHotKeys: [ShelfHotKey] = []
        var unregisteredCount = 0
        let monitor = CarbonHotKeyMonitor(
            hotKey: .toggleShelf,
            onPressed: {},
            register: { hotKey, _ in
                registeredHotKeys.append(hotKey)
                return CarbonHotKeyRegistration()
            },
            unregister: { _ in
                unregisteredCount += 1
            }
        )

        try monitor.start()
        try monitor.start()
        monitor.stop()
        monitor.stop()

        XCTAssertEqual(registeredHotKeys, [.toggleShelf])
        XCTAssertEqual(unregisteredCount, 1)
    }

    func testStartsOnceWhenFileDragPasteboardChanges() {
        let monitor = makeMonitor(snapshots: [
            DragPasteboardSnapshot(changeCount: 0, types: []),
            DragPasteboardSnapshot(changeCount: 1, types: [.fileURL]),
            DragPasteboardSnapshot(changeCount: 1, types: [.fileURL]),
        ])
        var startCount = 0
        monitor.onDragStarted = { _ in startCount += 1 }

        monitor.handleDragged()
        monitor.handleDragged()

        XCTAssertEqual(startCount, 1)
    }

    func testStartsForURLDragPasteboardChanges() {
        let monitor = makeMonitor(snapshots: [
            DragPasteboardSnapshot(changeCount: 0, types: []),
            DragPasteboardSnapshot(changeCount: 1, types: [.URL]),
        ])
        var didStart = false
        monitor.onDragStarted = { _ in didStart = true }

        monitor.handleDragged()

        XCTAssertTrue(didStart)
    }

    func testStartsForLegacyFilenameDragPasteboardChanges() {
        let legacyFilenameType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let monitor = makeMonitor(snapshots: [
            DragPasteboardSnapshot(changeCount: 0, types: []),
            DragPasteboardSnapshot(changeCount: 1, types: [legacyFilenameType]),
        ])
        var didStart = false
        monitor.onDragStarted = { _ in didStart = true }

        monitor.handleDragged()

        XCTAssertTrue(didStart)
    }

    func testStartsDragWithCurrentMouseLocation() {
        let monitor = makeMonitor(
            snapshots: [
                DragPasteboardSnapshot(changeCount: 0, types: []),
                DragPasteboardSnapshot(changeCount: 1, types: [.fileURL]),
            ],
            mouseLocations: [NSPoint(x: 20, y: 30)]
        )
        var startedLocations: [NSPoint] = []
        monitor.onDragStarted = { startedLocations.append($0) }

        monitor.handleDragged()

        XCTAssertEqual(startedLocations, [NSPoint(x: 20, y: 30)])
    }

    func testEndsWhenPasteboardChangesToUnsupportedPayload() {
        let monitor = makeMonitor(snapshots: [
            DragPasteboardSnapshot(changeCount: 0, types: []),
            DragPasteboardSnapshot(changeCount: 1, types: [.fileURL]),
            DragPasteboardSnapshot(changeCount: 2, types: [.string]),
        ])
        var endCount = 0
        monitor.onDragEnded = { endCount += 1 }

        monitor.handleDragged()
        monitor.handleDragged()

        XCTAssertEqual(endCount, 1)
    }

    func testPointerEndOnlyEndsActiveDragOnce() {
        let monitor = makeMonitor(snapshots: [
            DragPasteboardSnapshot(changeCount: 0, types: []),
            DragPasteboardSnapshot(changeCount: 1, types: [.fileURL]),
        ])
        var endCount = 0
        monitor.onDragEnded = { endCount += 1 }

        monitor.handleDragged()
        monitor.handlePointerEnded()
        monitor.handlePointerEnded()

        XCTAssertEqual(endCount, 1)
    }

    private func makeMonitor(
        snapshots: [DragPasteboardSnapshot],
        mouseLocations: [NSPoint] = []
    ) -> GlobalDragMonitor {
        var snapshots = snapshots
        var mouseLocations = mouseLocations
        return GlobalDragMonitor(
            pasteboardSnapshotProvider: {
                guard !snapshots.isEmpty else {
                    XCTFail("Unexpected pasteboard snapshot request")
                    return DragPasteboardSnapshot(changeCount: -1, types: [])
                }
                return snapshots.removeFirst()
            },
            mouseLocationProvider: {
                mouseLocations.isEmpty ? .zero : mouseLocations.removeFirst()
            }
        )
    }
}
