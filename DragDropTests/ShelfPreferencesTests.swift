import XCTest
@testable import DragDrop

final class ShelfPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "ShelfPreferencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testDefaultPolicyMatchesManualCleanupPolicy() {
        let preferences = ShelfPreferences(defaults: defaults)

        XCTAssertEqual(preferences.cleanupPolicy, .manualStorageCleanup)
    }

    func testForeverRetentionDisablesMaximumAge() {
        let preferences = ShelfPreferences(defaults: defaults)

        preferences.retentionOption = .forever

        XCTAssertNil(preferences.cleanupPolicy.maximumAge)
        XCTAssertEqual(preferences.cleanupPolicy.maximumTotalBytes, 1_000_000_000)
    }

    func testOffSizeLimitDisablesMaximumTotalBytes() {
        let preferences = ShelfPreferences(defaults: defaults)

        preferences.sizeLimitOption = .off

        XCTAssertEqual(preferences.cleanupPolicy.maximumAge, 30 * 24 * 60 * 60)
        XCTAssertNil(preferences.cleanupPolicy.maximumTotalBytes)
    }

    func testCustomValuesAreClampedBeforePersistence() {
        let preferences = ShelfPreferences(defaults: defaults)

        preferences.customRetentionDays = -10
        preferences.customSizeLimitMB = 0

        XCTAssertEqual(preferences.customRetentionDays, 1)
        XCTAssertEqual(preferences.customSizeLimitMB, 1)
        XCTAssertEqual(defaults.integer(forKey: ShelfPreferences.Keys.customRetentionDays), 1)
        XCTAssertEqual(defaults.integer(forKey: ShelfPreferences.Keys.customSizeLimitMB), 1)
    }

    func testValuesPersistAcrossPreferenceInstances() {
        let preferences = ShelfPreferences(defaults: defaults)

        preferences.retentionOption = .custom
        preferences.customRetentionDays = 14
        preferences.sizeLimitOption = .custom
        preferences.customSizeLimitMB = 2048

        let restored = ShelfPreferences(defaults: defaults)

        XCTAssertEqual(restored.retentionOption, .custom)
        XCTAssertEqual(restored.customRetentionDays, 14)
        XCTAssertEqual(restored.sizeLimitOption, .custom)
        XCTAssertEqual(restored.customSizeLimitMB, 2048)
        XCTAssertEqual(restored.cleanupPolicy.maximumAge, 14 * 24 * 60 * 60)
        XCTAssertEqual(restored.cleanupPolicy.maximumTotalBytes, 2_048_000_000)
    }
}
