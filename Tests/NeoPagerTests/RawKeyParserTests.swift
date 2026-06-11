import XCTest
import SwiftTUI
@testable import NeoPager

/// Tests for the vendored-SwiftTUI key decoder (#0004), including the printable
/// keys the pager binds for paging/quit (#0013, #0014).
final class RawKeyParserTests: XCTestCase {

    private func parse(_ s: String) -> [RawKeyEvent] {
        RawKeyParser.parse(s)
    }

    // MARK: - Printable keys (Space / b / q bindings)

    func testSpaceIsPrintableChar() {
        XCTAssertEqual(parse(" "), [.char(" ")])
    }

    func testBAndQArePrintableChars() {
        XCTAssertEqual(parse("b"), [.char("b")])
        XCTAssertEqual(parse("q"), [.char("q")])
    }

    func testMultiplePrintableChars() {
        XCTAssertEqual(parse("abc"), [.char("a"), .char("b"), .char("c")])
    }

    func testControlBytesBelowSpaceAreSkipped() {
        XCTAssertEqual(parse("\u{01}"), []) // Ctrl-A, not a printable char
    }

    // MARK: - Arrows

    func testCSIArrows() {
        XCTAssertEqual(parse("\u{1b}[A"), [.up])
        XCTAssertEqual(parse("\u{1b}[B"), [.down])
        XCTAssertEqual(parse("\u{1b}[C"), [.right])
        XCTAssertEqual(parse("\u{1b}[D"), [.left])
    }

    func testSS3Arrows() {
        XCTAssertEqual(parse("\u{1b}OA"), [.up])
        XCTAssertEqual(parse("\u{1b}OB"), [.down])
    }

    // MARK: - Page movement

    func testPageKeys() {
        XCTAssertEqual(parse("\u{1b}[5~"), [.pageUp])
        XCTAssertEqual(parse("\u{1b}[6~"), [.pageDown])
    }

    func testOptionArrowsXtermModifierForm() {
        XCTAssertEqual(parse("\u{1b}[1;3A"), [.pageUp])
        XCTAssertEqual(parse("\u{1b}[1;3B"), [.pageDown])
    }

    func testOptionArrowsEscEscForm() {
        XCTAssertEqual(parse("\u{1b}\u{1b}[A"), [.pageUp])
        XCTAssertEqual(parse("\u{1b}\u{1b}[B"), [.pageDown])
    }

    // MARK: - Esc / Enter / Backspace

    func testBareEscape() {
        XCTAssertEqual(parse("\u{1b}"), [.escape])
    }

    func testEnterAndBackspace() {
        XCTAssertEqual(parse("\r"), [.enter])
        XCTAssertEqual(parse("\n"), [.enter])
        XCTAssertEqual(parse("\u{7f}"), [.backspace])
        XCTAssertEqual(parse("\u{08}"), [.backspace])
    }

    // MARK: - Mixed chunks

    func testArrowFollowedByChar() {
        XCTAssertEqual(parse("\u{1b}[Bq"), [.down, .char("q")])
    }

    func testCtrlArrowFallsBackToPlainArrow() {
        // 1;5 is the Ctrl modifier; not Option, so it's a plain line move.
        XCTAssertEqual(parse("\u{1b}[1;5A"), [.up])
    }
}
