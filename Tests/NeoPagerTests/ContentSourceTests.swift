import XCTest
@testable import NeoPager

final class ContentSourceTests: XCTestCase {

    // MARK: - Line splitting

    func testTrailingNewlineDoesNotAddEmptyLine() {
        XCTAssertEqual(ContentSource.splitLines("a\nb\nc\n"), ["a", "b", "c"])
    }

    func testNoTrailingNewlineKeepsLastLine() {
        XCTAssertEqual(ContentSource.splitLines("a\nb"), ["a", "b"])
    }

    func testEmptyInputIsNoLines() {
        XCTAssertEqual(ContentSource.splitLines(""), [])
    }

    func testCRLFStripped() {
        XCTAssertEqual(ContentSource.splitLines("a\r\nb\r\n"), ["a", "b"])
    }

    func testBlankInteriorLinesPreserved() {
        XCTAssertEqual(ContentSource.splitLines("a\n\nb\n"), ["a", "", "b"])
    }

    // MARK: - Tab expansion (#0009)

    func testTabExpandsToNextEightColumnStop() {
        XCTAssertEqual(ContentSource.expandTabs("a\tb"), "a       b") // 'a' at col 0, tab -> 7 spaces to col 8
    }

    func testTabAtColumnZero() {
        XCTAssertEqual(ContentSource.expandTabs("\tx"), "        x") // 8 spaces
    }

    func testMultipleTabs() {
        XCTAssertEqual(ContentSource.expandTabs("ab\tcd\te"), "ab      cd      e")
    }

    func testLineWithoutTabsUnchanged() {
        XCTAssertEqual(ContentSource.expandTabs("no tabs here"), "no tabs here")
    }

    func testTabsExpandedDuringSplit() {
        XCTAssertEqual(ContentSource.splitLines("a\tb\n"), ["a       b"])
    }

    // MARK: - Lossy UTF-8

    func testInvalidUTF8DecodesLossily() {
        let data = Data([0x67, 0x6f, 0x6f, 0x64, 0xff, 0xfe]) // "good" + invalid bytes
        let decoded = ContentSource.decodeLossy(data)
        XCTAssertTrue(decoded.hasPrefix("good"))
        XCTAssertTrue(decoded.unicodeScalars.contains("\u{FFFD}"))
    }
}
