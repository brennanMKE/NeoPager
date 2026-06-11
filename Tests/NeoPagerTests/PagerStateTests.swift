import Combine
import XCTest
@testable import NeoPager

final class PagerStateTests: XCTestCase {

    private func makeLines(_ n: Int) -> [String] {
        (1...n).map { "line \($0)" }
    }

    // MARK: - Line movement & clamping

    func testStartsAtTop() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        XCTAssertEqual(s.offset, 0)
        XCTAssertTrue(s.atTop)
        XCTAssertFalse(s.atEnd)
    }

    func testLineDownAndUp() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        s.lineDown()
        XCTAssertEqual(s.offset, 1)
        s.lineDown()
        XCTAssertEqual(s.offset, 2)
        s.lineUp()
        XCTAssertEqual(s.offset, 1)
    }

    func testLineUpClampsAtTop() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        s.lineUp()
        s.lineUp()
        XCTAssertEqual(s.offset, 0, "scrolling up past the top is a no-op")
        XCTAssertTrue(s.atTop)
    }

    func testLineDownClampsAtBottomAndNeverExits() {
        let s = PagerState(lines: makeLines(15), viewportHeight: 10) // maxOffset = 5
        for _ in 0..<100 { s.lineDown() }
        XCTAssertEqual(s.offset, 5, "offset clamps to lineCount - viewportHeight")
        XCTAssertTrue(s.atEnd)
        // Reaching the bottom is a no-op, not an exit: further movement still clamps.
        s.lineDown()
        XCTAssertEqual(s.offset, 5)
    }

    // MARK: - Page movement

    func testPageMovesByViewportHeight() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10) // maxOffset = 90
        s.pageDown()
        XCTAssertEqual(s.offset, 10)
        s.pageDown()
        XCTAssertEqual(s.offset, 20)
        s.pageUp()
        XCTAssertEqual(s.offset, 10)
    }

    func testPageDownClampsAtBottom() {
        let s = PagerState(lines: makeLines(25), viewportHeight: 10) // maxOffset = 15
        s.pageDown() // 10
        s.pageDown() // would be 20 -> clamps to 15
        XCTAssertEqual(s.offset, 15)
        XCTAssertTrue(s.atEnd)
    }

    func testPageUpClampsAtTop() {
        let s = PagerState(lines: makeLines(25), viewportHeight: 10)
        s.pageDown() // 10
        s.pageUp()   // 0
        s.pageUp()   // clamps at 0
        XCTAssertEqual(s.offset, 0)
    }

    // MARK: - Content shorter than the viewport

    func testShortContentAllMovementIsNoOp() {
        let s = PagerState(lines: makeLines(3), viewportHeight: 10) // maxOffset = 0
        XCTAssertEqual(s.maxOffset, 0)
        XCTAssertTrue(s.atEnd)
        XCTAssertTrue(s.atTop)
        s.lineDown(); s.pageDown(); s.lineUp()
        XCTAssertEqual(s.offset, 0)
        XCTAssertEqual(s.positionPercent, 100)
    }

    // MARK: - Position percentage

    func testPositionPercent() {
        let s = PagerState(lines: makeLines(110), viewportHeight: 10) // maxOffset = 100
        XCTAssertEqual(s.positionPercent, 0)
        s.pageDown() // offset 10
        XCTAssertEqual(s.positionPercent, 10)
        for _ in 0..<100 { s.lineDown() } // clamp to 100
        XCTAssertEqual(s.positionPercent, 100)
        XCTAssertTrue(s.atEnd)
    }

    // MARK: - Resize re-clamping

    func testShrinkViewportReclampsOffset() {
        let s = PagerState(lines: makeLines(20), viewportHeight: 10) // maxOffset = 10
        for _ in 0..<100 { s.lineDown() } // offset 10 (at end)
        XCTAssertEqual(s.offset, 10)
        // Grow the viewport: maxOffset shrinks to 5, offset must re-clamp down.
        s.setViewportHeight(15) // maxOffset = 5
        XCTAssertEqual(s.offset, 5, "growing the viewport re-clamps the offset down")
        XCTAssertTrue(s.atEnd)
    }

    func testGrowViewportToFitAllContent() {
        let s = PagerState(lines: makeLines(8), viewportHeight: 4)
        s.pageDown() // offset 4 (maxOffset = 4)
        XCTAssertEqual(s.offset, 4)
        s.setViewportHeight(20) // everything fits now
        XCTAssertEqual(s.offset, 0)
        XCTAssertEqual(s.maxOffset, 0)
    }

    // MARK: - Visible slice

    func testVisibleLinesSlice() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        XCTAssertEqual(Array(s.visibleLines()), (1...10).map { "line \($0)" })
        s.pageDown() // offset 10
        XCTAssertEqual(Array(s.visibleLines()), (11...20).map { "line \($0)" })
    }

    func testVisibleLinesNearBottomDoesNotOverflow() {
        let s = PagerState(lines: makeLines(12), viewportHeight: 10) // maxOffset = 2
        for _ in 0..<100 { s.lineDown() } // offset 2
        let visible = Array(s.visibleLines())
        XCTAssertEqual(visible.count, 10)
        XCTAssertEqual(visible.last, "line 12")
    }

    func testVisibleLinesEmptyWhenNoViewport() {
        let s = PagerState(lines: makeLines(10), viewportHeight: 0)
        XCTAssertTrue(s.visibleLines().isEmpty)
    }

    // MARK: - Jump to top/bottom (#0015) and half-page (#0017)

    func testScrollToBottomAndTop() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10) // maxOffset 90
        s.scrollToBottom()
        XCTAssertEqual(s.offset, 90)
        XCTAssertTrue(s.atEnd)
        s.scrollToTop()
        XCTAssertEqual(s.offset, 0)
        XCTAssertTrue(s.atTop)
    }

    func testScrollToTopBottomAreNoOpsAtEnds() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        s.scrollToTop()                 // already at top
        XCTAssertEqual(s.offset, 0)
        s.scrollToBottom(); s.scrollToBottom() // second is a no-op
        XCTAssertEqual(s.offset, 90)
    }

    func testHalfPageMovesByHalfViewport() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10) // half = 5
        s.halfPageDown()
        XCTAssertEqual(s.offset, 5)
        s.halfPageDown()
        XCTAssertEqual(s.offset, 10)
        s.halfPageUp()
        XCTAssertEqual(s.offset, 5)
    }

    func testHalfPageClampsAndAtLeastOne() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 1) // half = max(1, 0) = 1
        s.halfPageDown()
        XCTAssertEqual(s.offset, 1, "half of a 1-row viewport still moves at least one line")
        let t = PagerState(lines: makeLines(12), viewportHeight: 10) // maxOffset 2, half 5
        t.halfPageDown()
        XCTAssertEqual(t.offset, 2, "clamps at maxOffset")
    }

    // MARK: - Change notifications

    func testObjectWillChangeFiresOnRealMoveOnly() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        var count = 0
        let c = s.objectWillChange.sink { count += 1 }
        defer { c.cancel() }

        s.lineDown()        // real move -> 1
        XCTAssertEqual(count, 1)
        s.lineUp()          // real move -> 2
        XCTAssertEqual(count, 2)
        s.lineUp()          // no-op at top -> still 2
        XCTAssertEqual(count, 2)
    }
}
