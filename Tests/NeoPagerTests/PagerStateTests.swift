import Combine
import Testing
@testable import NeoPager

@Suite struct PagerStateTests {

    private func makeLines(_ n: Int) -> [String] {
        (1...n).map { "line \($0)" }
    }

    // MARK: - Line movement & clamping

    @Test func startsAtTop() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        #expect(s.offset == 0)
        #expect(s.atTop)
        #expect(!s.atEnd)
    }

    @Test func lineDownAndUp() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        s.lineDown()
        #expect(s.offset == 1)
        s.lineDown()
        #expect(s.offset == 2)
        s.lineUp()
        #expect(s.offset == 1)
    }

    @Test func lineUpClampsAtTop() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        s.lineUp()
        s.lineUp()
        #expect(s.offset == 0, "scrolling up past the top is a no-op")
        #expect(s.atTop)
    }

    @Test func lineDownClampsAtBottomAndNeverExits() {
        let s = PagerState(lines: makeLines(15), viewportHeight: 10) // maxOffset = 5
        for _ in 0..<100 { s.lineDown() }
        #expect(s.offset == 5, "offset clamps to lineCount - viewportHeight")
        #expect(s.atEnd)
        // Reaching the bottom is a no-op, not an exit: further movement still clamps.
        s.lineDown()
        #expect(s.offset == 5)
    }

    // MARK: - Page movement

    @Test func pageMovesByViewportHeight() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10) // maxOffset = 90
        s.pageDown()
        #expect(s.offset == 10)
        s.pageDown()
        #expect(s.offset == 20)
        s.pageUp()
        #expect(s.offset == 10)
    }

    @Test func pageDownClampsAtBottom() {
        let s = PagerState(lines: makeLines(25), viewportHeight: 10) // maxOffset = 15
        s.pageDown() // 10
        s.pageDown() // would be 20 -> clamps to 15
        #expect(s.offset == 15)
        #expect(s.atEnd)
    }

    @Test func pageUpClampsAtTop() {
        let s = PagerState(lines: makeLines(25), viewportHeight: 10)
        s.pageDown() // 10
        s.pageUp()   // 0
        s.pageUp()   // clamps at 0
        #expect(s.offset == 0)
    }

    // MARK: - Content shorter than the viewport

    @Test func shortContentAllMovementIsNoOp() {
        let s = PagerState(lines: makeLines(3), viewportHeight: 10) // maxOffset = 0
        #expect(s.maxOffset == 0)
        #expect(s.atEnd)
        #expect(s.atTop)
        s.lineDown(); s.pageDown(); s.lineUp()
        #expect(s.offset == 0)
        #expect(s.positionPercent == 100)
    }

    // MARK: - Position percentage

    @Test func positionPercent() {
        let s = PagerState(lines: makeLines(110), viewportHeight: 10) // maxOffset = 100
        #expect(s.positionPercent == 0)
        s.pageDown() // offset 10
        #expect(s.positionPercent == 10)
        for _ in 0..<100 { s.lineDown() } // clamp to 100
        #expect(s.positionPercent == 100)
        #expect(s.atEnd)
    }

    // MARK: - Resize re-clamping

    @Test func shrinkViewportReclampsOffset() {
        let s = PagerState(lines: makeLines(20), viewportHeight: 10) // maxOffset = 10
        for _ in 0..<100 { s.lineDown() } // offset 10 (at end)
        #expect(s.offset == 10)
        // Grow the viewport: maxOffset shrinks to 5, offset must re-clamp down.
        s.setViewportHeight(15) // maxOffset = 5
        #expect(s.offset == 5, "growing the viewport re-clamps the offset down")
        #expect(s.atEnd)
    }

    @Test func growViewportToFitAllContent() {
        let s = PagerState(lines: makeLines(8), viewportHeight: 4)
        s.pageDown() // offset 4 (maxOffset = 4)
        #expect(s.offset == 4)
        s.setViewportHeight(20) // everything fits now
        #expect(s.offset == 0)
        #expect(s.maxOffset == 0)
    }

    // MARK: - Visible slice

    @Test func visibleLinesSlice() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        #expect(s.visibleLines() == (1...10).map { "line \($0)" })
        s.pageDown() // offset 10
        #expect(s.visibleLines() == (11...20).map { "line \($0)" })
    }

    @Test func visibleLinesNearBottomDoesNotOverflow() {
        let s = PagerState(lines: makeLines(12), viewportHeight: 10) // maxOffset = 2
        for _ in 0..<100 { s.lineDown() } // offset 2
        let visible = s.visibleLines()
        #expect(visible.count == 10)
        #expect(visible.last == "line 12")
    }

    @Test func visibleLinesEmptyWhenNoViewport() {
        let s = PagerState(lines: makeLines(10), viewportHeight: 0)
        #expect(s.visibleLines().isEmpty)
    }

    // MARK: - Jump to top/bottom (#0015) and half-page (#0017)

    @Test func scrollToBottomAndTop() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10) // maxOffset 90
        s.scrollToBottom()
        #expect(s.offset == 90)
        #expect(s.atEnd)
        s.scrollToTop()
        #expect(s.offset == 0)
        #expect(s.atTop)
    }

    @Test func scrollToTopBottomAreNoOpsAtEnds() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        s.scrollToTop()                 // already at top
        #expect(s.offset == 0)
        s.scrollToBottom(); s.scrollToBottom() // second is a no-op
        #expect(s.offset == 90)
    }

    @Test func halfPageMovesByHalfViewport() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10) // half = 5
        s.halfPageDown()
        #expect(s.offset == 5)
        s.halfPageDown()
        #expect(s.offset == 10)
        s.halfPageUp()
        #expect(s.offset == 5)
    }

    @Test func halfPageClampsAndAtLeastOne() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 1) // half = max(1, 0) = 1
        s.halfPageDown()
        #expect(s.offset == 1, "half of a 1-row viewport still moves at least one line")
        let t = PagerState(lines: makeLines(12), viewportHeight: 10) // maxOffset 2, half 5
        t.halfPageDown()
        #expect(t.offset == 2, "clamps at maxOffset")
    }

    // MARK: - Wrapping (#0019)

    private func wrapLines() -> [String] {
        ["short", String(repeating: "x", count: 25), "end"]
    }

    @Test func wrapSplitsLongLineIntoDisplayRows() {
        let s = PagerState(lines: wrapLines(), viewportHeight: 10, viewportWidth: 10, wrapEnabled: true)
        #expect(s.lineCount == 3)
        #expect(s.rowCount == 5) // short | x*10 | x*10 | x*5 | end
        #expect(s.displayRows.map(\.bufferLine) == [0, 1, 1, 1, 2])
        #expect(s.displayRows[1].text == String(repeating: "x", count: 10))
        #expect(s.displayRows[3].text == String(repeating: "x", count: 5))
    }

    @Test func chopModeIsOneRowPerLine() {
        let s = PagerState(lines: wrapLines(), viewportHeight: 10, viewportWidth: 10, wrapEnabled: false)
        #expect(s.rowCount == 3)
        #expect(s.displayRows[1].text.count == 25, "chop keeps the full line; the view truncates")
    }

    @Test func widthZeroMeansNoWrap() {
        let s = PagerState(lines: wrapLines(), viewportHeight: 10, viewportWidth: 0, wrapEnabled: true)
        #expect(s.rowCount == 3)
    }

    @Test func bottomBufferLineInWrapMode() {
        let s = PagerState(lines: wrapLines(), viewportHeight: 10, viewportWidth: 10) // all 5 rows visible
        #expect(s.bottomBufferLine == 3)
        #expect(s.lineCount == 3)
    }

    @Test func scrollingMovesThroughDisplayRows() {
        let s = PagerState(lines: wrapLines(), viewportHeight: 2, viewportWidth: 10)
        #expect(s.rowCount == 5)
        #expect(s.maxOffset == 3)
        s.lineDown()
        #expect(s.offset == 1)
        #expect(s.visibleLines() == [String(repeating: "x", count: 10), String(repeating: "x", count: 10)])
        #expect(s.bottomBufferLine == 2, "both visible rows belong to buffer line 2 (1-based)")
    }

    @Test func toggleWrapPreservesTopBufferLine() {
        let s = PagerState(lines: wrapLines(), viewportHeight: 2, viewportWidth: 10)
        s.lineDown() // offset 1 -> top display row belongs to buffer line index 1
        s.setWrap(false)
        #expect(!s.wrapEnabled)
        #expect(s.rowCount == 3)
        #expect(s.offset == 1, "top stays on the same buffer line after un-wrapping")
    }

    @Test func resizeRewrapsKeepingTopLine() {
        let s = PagerState(lines: wrapLines(), viewportHeight: 3, viewportWidth: 10)
        // scroll so the top is inside the long line (buffer line 1)
        s.lineDown(); s.lineDown() // offset 2, top display row is the 2nd x-segment (buffer line 1)
        #expect(s.displayRows[s.offset].bufferLine == 1)
        s.setViewport(height: 3, width: 5) // narrower: the 25-char line now wraps into 5 rows
        #expect(s.displayRows[s.offset].bufferLine == 1, "still anchored on buffer line 1 after re-wrap")
    }

    // MARK: - Horizontal scroll in chop mode (#0016)

    @Test func horizontalScrollWindowsChoppedLine() {
        let s = PagerState(lines: ["abcdefghij"], viewportHeight: 1, viewportWidth: 4, wrapEnabled: false)
        #expect(s.visibleLines() == ["abcd"])
        s.scrollRight(by: 4)
        #expect(s.horizontalOffset == 4)
        #expect(s.visibleLines() == ["efgh"])
    }

    @Test func horizontalScrollClampsAtBothEnds() {
        let s = PagerState(lines: ["abcdefghij"], viewportHeight: 1, viewportWidth: 4, wrapEnabled: false)
        s.scrollRight(by: 100)                  // max = 10 - 4 = 6
        #expect(s.horizontalOffset == 6)
        #expect(s.visibleLines() == ["ghij"])
        s.scrollLeft(by: 100)                   // clamp at 0
        #expect(s.horizontalOffset == 0)
        #expect(s.visibleLines() == ["abcd"])
    }

    @Test func horizontalScrollIsNoOpInWrapMode() {
        let s = PagerState(lines: [String(repeating: "x", count: 25)], viewportHeight: 5, viewportWidth: 10, wrapEnabled: true)
        s.scrollRight(by: 8)
        #expect(s.horizontalOffset == 0, "wrap hides nothing, so horizontal scroll is a no-op")
        #expect(s.maxHorizontalOffset == 0)
    }

    @Test func toggleToWrapResetsHorizontalOffset() {
        let s = PagerState(lines: ["abcdefghij"], viewportHeight: 1, viewportWidth: 4, wrapEnabled: false)
        s.scrollRight(by: 4)
        #expect(s.horizontalOffset == 4)
        s.setWrap(true)
        #expect(s.horizontalOffset == 0)
    }

    // MARK: - Help overlay (#0020)

    @Test func helpFlagTogglesAndPreservesScroll() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        s.pageDown() // offset 10
        #expect(!s.showingHelp)
        s.setShowingHelp(true)
        #expect(s.showingHelp)
        #expect(s.offset == 10, "showing help leaves the scroll position untouched")
        s.setShowingHelp(false)
        #expect(!s.showingHelp)
        #expect(s.offset == 10)
    }

    // MARK: - Change notifications

    @Test func objectWillChangeFiresOnRealMoveOnly() {
        let s = PagerState(lines: makeLines(100), viewportHeight: 10)
        var count = 0
        let c = s.objectWillChange.sink { count += 1 }
        defer { c.cancel() }

        s.lineDown()        // real move -> 1
        #expect(count == 1)
        s.lineUp()          // real move -> 2
        #expect(count == 2)
        s.lineUp()          // no-op at top -> still 2
        #expect(count == 2)
    }
}
