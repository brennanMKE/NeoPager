import Combine

/// One rendered row of the viewport: a (possibly wrapped) segment of a buffer line,
/// tagged with the index of the buffer line it came from.
nonisolated struct DisplayRow: Equatable {
    /// 0-based index into `PagerState.lines` this row belongs to.
    let bufferLine: Int
    /// The text of this row — a full buffer line (chop mode) or a width-wide
    /// wrapped segment (wrap mode).
    let text: String
}

/// Observable scroll model for the pager.
///
/// Pure logic — no SwiftTUI imports — so the clamp/boundary behavior is testable
/// without a terminal. SwiftTUI views observe it through Combine `ObservableObject`.
///
/// The scroll offset indexes **display rows**, not buffer lines (#0019): when
/// wrapping is on, a buffer line wider than the viewport becomes several display
/// rows. With `viewportWidth == 0` (or wrapping off) there is exactly one display
/// row per buffer line, so the model reduces to the simple 1:1 case.
nonisolated final class PagerState: ObservableObject {
    /// The full content buffer, loaded up front. Immutable for the pager's lifetime.
    let lines: [String]

    /// Number of display rows visible at once (terminal height minus the status bar).
    private(set) var viewportHeight: Int

    /// Terminal width in columns. `0` means "unbounded" — no wrapping.
    private(set) var viewportWidth: Int

    /// When true, long lines wrap onto continuation rows; when false they are chopped
    /// (one display row per buffer line) and the view truncates to width (#0016).
    private(set) var wrapEnabled: Bool

    /// Index of the first visible display row (0-based). Always within `0 ... maxOffset`.
    private(set) var offset: Int = 0

    /// Columns scrolled to the right in chop mode (#0016). Always 0 in wrap mode,
    /// where nothing is hidden off the right edge.
    private(set) var horizontalOffset: Int = 0

    /// The flattened display rows for the current width / wrap mode.
    private(set) var displayRows: [DisplayRow] = []

    let objectWillChange = ObservableObjectPublisher()

    init(lines: [String], viewportHeight: Int = 0, viewportWidth: Int = 0, wrapEnabled: Bool = true) {
        self.lines = lines
        self.viewportHeight = max(0, viewportHeight)
        self.viewportWidth = max(0, viewportWidth)
        self.wrapEnabled = wrapEnabled
        rebuildDisplayRows()
    }

    /// Number of buffer lines (the denominator of the `line/total` indicator).
    var lineCount: Int { lines.count }

    /// Number of display rows after wrapping.
    var rowCount: Int { displayRows.count }

    /// Largest valid offset — the last display row sits at the bottom of the viewport.
    /// Zero when all content fits, so there is nothing to scroll.
    var maxOffset: Int { max(0, rowCount - viewportHeight) }

    /// True when the last display row is visible (including when all content fits).
    var atEnd: Bool { offset >= maxOffset }

    /// True when the first display row is visible.
    var atTop: Bool { offset <= 0 }

    /// Scroll progress as a whole percentage — 0 at the top, 100 at the bottom clamp.
    var positionPercent: Int {
        guard maxOffset > 0 else { return 100 }
        return Int((Double(offset) / Double(maxOffset) * 100).rounded())
    }

    /// 1-based buffer line number of the bottom visible display row, for the status
    /// bar's `line/total`. Zero when there is no content.
    var bottomBufferLine: Int {
        guard !displayRows.isEmpty, viewportHeight > 0 else { return 0 }
        let lastVisible = min(offset + viewportHeight - 1, rowCount - 1)
        return displayRows[max(0, lastVisible)].bufferLine + 1
    }

    // MARK: - Movement (all operate in display-row space)

    /// Scroll up one row. No-op (no wrap, no bell, no exit) when already at the top.
    func lineUp() { setOffset(offset - 1) }

    /// Scroll down one row. No-op when already at the bottom — reaching the bottom
    /// never exits the pager (the original sin of `more`).
    func lineDown() { setOffset(offset + 1) }

    /// Scroll up one full viewport. Clamps at the top.
    func pageUp() { setOffset(offset - viewportHeight) }

    /// Scroll down one full viewport. Clamps at the bottom.
    func pageDown() { setOffset(offset + viewportHeight) }

    /// Scroll up half a viewport (#0017).
    func halfPageUp() { setOffset(offset - max(1, viewportHeight / 2)) }

    /// Scroll down half a viewport (#0017).
    func halfPageDown() { setOffset(offset + max(1, viewportHeight / 2)) }

    /// Jump to the first row (#0015). No-op when already at the top.
    func scrollToTop() { setOffset(0) }

    /// Jump so the last row sits at the bottom (#0015). No-op when already at the end.
    func scrollToBottom() { setOffset(maxOffset) }

    /// The furthest right the view can scroll: enough to bring the end of the widest
    /// currently-visible line to the right edge. Always 0 in wrap mode (#0016).
    var maxHorizontalOffset: Int {
        guard !wrapEnabled, viewportWidth > 0 else { return 0 }
        let widest = visibleDisplayRows().map(\.text.count).max() ?? 0
        return max(0, widest - viewportWidth)
    }

    /// Scroll right by `step` columns (chop mode only; #0016). Clamps so the widest
    /// visible line's end doesn't scroll past the right edge.
    func scrollRight(by step: Int = 8) { setHorizontalOffset(horizontalOffset + step) }

    /// Scroll left by `step` columns. Clamps at column 0.
    func scrollLeft(by step: Int = 8) { setHorizontalOffset(horizontalOffset - step) }

    // MARK: - Geometry / mode changes

    /// Updates the viewport height and re-clamps the offset so the view stays valid.
    func setViewportHeight(_ height: Int) {
        setViewport(height: height, width: viewportWidth)
    }

    /// Updates the full viewport geometry (height + width), re-wraps for the new
    /// width, and keeps the top buffer line stable across the reflow (#0009/#0019).
    func setViewport(height: Int, width: Int) {
        let newHeight = max(0, height)
        let newWidth = max(0, width)
        guard newHeight != viewportHeight || newWidth != viewportWidth else { return }
        let topLine = currentTopBufferLine()
        objectWillChange.send()
        viewportHeight = newHeight
        viewportWidth = newWidth
        rebuildDisplayRows()
        offset = clampedOffset(firstRowIndex(ofBufferLine: topLine))
        horizontalOffset = min(horizontalOffset, maxHorizontalOffset)
    }

    /// Toggles wrap vs chop, re-wrapping and keeping the top buffer line stable (#0019).
    func setWrap(_ enabled: Bool) {
        guard enabled != wrapEnabled else { return }
        let topLine = currentTopBufferLine()
        objectWillChange.send()
        wrapEnabled = enabled
        horizontalOffset = 0 // wrap hides nothing; chop starts un-scrolled
        rebuildDisplayRows()
        offset = clampedOffset(firstRowIndex(ofBufferLine: topLine))
    }

    // MARK: - Rendering

    /// The display rows currently visible, top-aligned.
    func visibleDisplayRows() -> ArraySlice<DisplayRow> {
        guard viewportHeight > 0, !displayRows.isEmpty else { return [] }
        let end = min(offset + viewportHeight, rowCount)
        let start = min(offset, end)
        return displayRows[start..<end]
    }

    /// The visible text for each row, already windowed to the viewport width: in wrap
    /// mode the rows are width-wide segments; in chop mode the horizontal window
    /// `[horizontalOffset, +viewportWidth)` is applied so the view renders directly.
    func visibleLines() -> [String] {
        let rows = visibleDisplayRows()
        if wrapEnabled || viewportWidth <= 0 {
            return rows.map(\.text)
        }
        return rows.map { horizontalWindow($0.text) }
    }

    /// Applies the chop-mode horizontal window to one row's text.
    private func horizontalWindow(_ text: String) -> String {
        let width = viewportWidth
        guard width > 0 else { return text }
        guard horizontalOffset > 0 else {
            return text.count > width ? String(text.prefix(width)) : text
        }
        guard text.count > horizontalOffset else { return "" }
        let start = text.index(text.startIndex, offsetBy: horizontalOffset)
        let end = text.index(start, offsetBy: width, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end])
    }

    // MARK: - Internals

    private func rebuildDisplayRows() {
        var rows: [DisplayRow] = []
        rows.reserveCapacity(lines.count)
        let width = viewportWidth
        for (index, line) in lines.enumerated() {
            if wrapEnabled, width > 0, line.count > width {
                var start = line.startIndex
                while start < line.endIndex {
                    let end = line.index(start, offsetBy: width, limitedBy: line.endIndex) ?? line.endIndex
                    rows.append(DisplayRow(bufferLine: index, text: String(line[start..<end])))
                    start = end
                }
            } else {
                rows.append(DisplayRow(bufferLine: index, text: line))
            }
        }
        displayRows = rows
    }

    /// The buffer line shown at the top of the viewport right now (used to keep the
    /// reading position stable across a re-wrap).
    private func currentTopBufferLine() -> Int {
        guard !displayRows.isEmpty else { return 0 }
        return displayRows[min(max(0, offset), displayRows.count - 1)].bufferLine
    }

    /// Index of the first display row belonging to `bufferLine` (or later).
    private func firstRowIndex(ofBufferLine bufferLine: Int) -> Int {
        displayRows.firstIndex { $0.bufferLine >= bufferLine } ?? 0
    }

    private func clampedOffset(_ value: Int) -> Int {
        min(max(0, value), maxOffset)
    }

    private func setOffset(_ newValue: Int) {
        let clamped = clampedOffset(newValue)
        // No-op past either end: don't emit a change, so the view doesn't repaint.
        guard clamped != offset else { return }
        objectWillChange.send()
        offset = clamped
    }

    private func setHorizontalOffset(_ newValue: Int) {
        let clamped = min(max(0, newValue), maxHorizontalOffset)
        guard clamped != horizontalOffset else { return }
        objectWillChange.send()
        horizontalOffset = clamped
    }
}
