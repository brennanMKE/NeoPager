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

    // MARK: - Tab expansion (#0009)

    @Test func tabExpandsToNextEightColumnStop() {
        #expect(ContentSource.expandTabs("a\tb") == "a       b") // 'a' at col 0, tab -> 7 spaces to col 8
    }

    @Test func tabAtColumnZero() {
        #expect(ContentSource.expandTabs("\tx") == "        x") // 8 spaces
    }

    @Test func multipleTabs() {
        #expect(ContentSource.expandTabs("ab\tcd\te") == "ab      cd      e")
    }

    @Test func lineWithoutTabsUnchanged() {
        #expect(ContentSource.expandTabs("no tabs here") == "no tabs here")
    }

    @Test func tabsExpandedDuringSplit() {
        #expect(ContentSource.splitLines("a\tb\n") == ["a       b"])
    }

    // MARK: - Lossy UTF-8

    @Test func invalidUTF8DecodesLossily() {
        let data = Data([0x67, 0x6f, 0x6f, 0x64, 0xff, 0xfe]) // "good" + invalid bytes
        let decoded = ContentSource.decodeLossy(data)
        #expect(decoded.hasPrefix("good"))
        #expect(decoded.unicodeScalars.contains("\u{FFFD}"))
    }
}
