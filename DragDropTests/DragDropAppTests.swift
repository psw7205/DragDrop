import XCTest
@testable import DragDrop

final class DragDropAppTests: XCTestCase {
    func testSettingsSceneUsesPreferencesView() {
        let settingsSceneType = String(reflecting: type(of: DragDropApp().body))

        XCTAssertTrue(settingsSceneType.contains("PreferencesView"), settingsSceneType)
        XCTAssertFalse(settingsSceneType.contains("EmptyView"), settingsSceneType)
    }
}
