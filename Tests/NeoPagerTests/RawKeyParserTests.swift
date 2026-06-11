import Testing
import SwiftTUI
@testable import NeoPager

/// Tests for the vendored-SwiftTUI key decoder (#0004), including the printable
/// keys the pager binds for paging/quit (#0013, #0014).
@Suite struct RawKeyParserTests {

    private func parse(_ s: String) -> [RawKeyEvent] {
        RawKeyParser.parse(s)
    }

    // MARK: - Printable keys (Space / b / q bindings)

    @Test func spaceIsPrintableChar() {
        #expect(parse(" ") == [.char(" ")])
    }

    @Test func bAndQArePrintableChars() {
        #expect(parse("b") == [.char("b")])
        #expect(parse("q") == [.char("q")])
    }

    @Test func multiplePrintableChars() {
        #expect(parse("abc") == [.char("a"), .char("b"), .char("c")])
    }

    @Test func controlBytesBelowSpaceAreSkipped() {
        #expect(parse("\u{01}") == []) // Ctrl-A, not a printable char
    }

    // MARK: - Arrows

    @Test func csiArrows() {
        #expect(parse("\u{1b}[A") == [.up])
        #expect(parse("\u{1b}[B") == [.down])
        #expect(parse("\u{1b}[C") == [.right])
        #expect(parse("\u{1b}[D") == [.left])
    }

    @Test func ss3Arrows() {
        #expect(parse("\u{1b}OA") == [.up])
        #expect(parse("\u{1b}OB") == [.down])
    }

    // MARK: - Page movement

    @Test func pageKeys() {
        #expect(parse("\u{1b}[5~") == [.pageUp])
        #expect(parse("\u{1b}[6~") == [.pageDown])
    }

    @Test func optionArrowsXtermModifierForm() {
        #expect(parse("\u{1b}[1;3A") == [.pageUp])
        #expect(parse("\u{1b}[1;3B") == [.pageDown])
    }

    @Test func optionArrowsEscEscForm() {
        #expect(parse("\u{1b}\u{1b}[A") == [.pageUp])
        #expect(parse("\u{1b}\u{1b}[B") == [.pageDown])
    }

    // MARK: - Home / End (#0015)

    @Test func homeAndEndCSI() {
        #expect(parse("\u{1b}[H") == [.home])
        #expect(parse("\u{1b}[F") == [.end])
    }

    @Test func homeAndEndVT220Tilde() {
        #expect(parse("\u{1b}[1~") == [.home])
        #expect(parse("\u{1b}[7~") == [.home])
        #expect(parse("\u{1b}[4~") == [.end])
        #expect(parse("\u{1b}[8~") == [.end])
    }

    @Test func homeAndEndSS3() {
        #expect(parse("\u{1b}OH") == [.home])
        #expect(parse("\u{1b}OF") == [.end])
    }

    // MARK: - F1 (#0020)

    @Test func f1KeySS3AndCSI() {
        #expect(parse("\u{1b}OP") == [.f1])    // SS3 form
        #expect(parse("\u{1b}[11~") == [.f1])  // CSI form
    }

    // MARK: - Esc / Enter / Backspace

    @Test func bareEscape() {
        #expect(parse("\u{1b}") == [.escape])
    }

    @Test func enterAndBackspace() {
        #expect(parse("\r") == [.enter])
        #expect(parse("\n") == [.enter])
        #expect(parse("\u{7f}") == [.backspace])
        #expect(parse("\u{08}") == [.backspace])
    }

    // MARK: - Mixed chunks

    @Test func arrowFollowedByChar() {
        #expect(parse("\u{1b}[Bq") == [.down, .char("q")])
    }

    @Test func ctrlArrowFallsBackToPlainArrow() {
        // 1;5 is the Ctrl modifier; not Option, so it's a plain line move.
        #expect(parse("\u{1b}[1;5A") == [.up])
    }
}
