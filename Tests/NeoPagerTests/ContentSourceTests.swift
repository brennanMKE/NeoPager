import Foundation
import Testing
@testable import NeoPager

@Suite struct ContentSourceTests {

    // MARK: - Line splitting

    @Test func trailingNewlineDoesNotAddEmptyLine() {
        #expect(ContentSource.splitLines("a\nb\nc\n") == ["a", "b", "c"])
    }

    @Test func noTrailingNewlineKeepsLastLine() {
        #expect(ContentSource.splitLines("a\nb") == ["a", "b"])
    }

    @Test func emptyInputIsNoLines() {
        #expect(ContentSource.splitLines("") == [])
    }

    @Test func crlfStripped() {
        #expect(ContentSource.splitLines("a\r\nb\r\n") == ["a", "b"])
    }

    @Test func blankInteriorLinesPreserved() {
        #expect(ContentSource.splitLines("a\n\nb\n") == ["a", "", "b"])
    }

    @Test func splitLinesLeavesTabsAndEscapesForTheParser() {
        // Tab expansion / escape stripping now happen in AnsiParser, not splitLines.
        #expect(ContentSource.splitLines("a\tb\n") == ["a\tb"])
    }

    // MARK: - Lossy UTF-8

    @Test func invalidUTF8DecodesLossily() {
        let data = Data([0x67, 0x6f, 0x6f, 0x64, 0xff, 0xfe]) // "good" + invalid bytes
        let decoded = ContentSource.decodeLossy(data)
        #expect(decoded.hasPrefix("good"))
        #expect(decoded.unicodeScalars.contains("\u{FFFD}"))
    }
}
