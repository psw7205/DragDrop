import XCTest
@testable import DragDrop

final class URLDetectionTests: XCTestCase {

    private func simulateURLDetection(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"),
              let parsedURL = URL(string: trimmed),
              let scheme = parsedURL.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return false
        }
        return true
    }

    func testHTTPURL() {
        XCTAssertTrue(simulateURLDetection("http://example.com"))
    }

    func testHTTPSURL() {
        XCTAssertTrue(simulateURLDetection("https://github.com/repo"))
    }

    func testHTTPSWithWhitespace() {
        XCTAssertTrue(simulateURLDetection("  https://example.com  "))
    }

    func testMultilineText() {
        XCTAssertFalse(simulateURLDetection("https://example.com\nhello"))
    }

    func testFTPScheme() {
        XCTAssertFalse(simulateURLDetection("ftp://files.example.com"))
    }

    func testPlainText() {
        XCTAssertFalse(simulateURLDetection("just some text"))
    }

    func testEmptyString() {
        XCTAssertFalse(simulateURLDetection(""))
    }

    func testURLWithPath() {
        XCTAssertTrue(simulateURLDetection("https://example.com/path/to/page?q=1"))
    }
}
