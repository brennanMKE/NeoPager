import Combine
import Foundation

/// One rendered row of the viewport: a (possibly wrapped) segment of a buffer line,
/// tagged with the index of the buffer line it came from.
nonisolated struct DisplayRow: Equatable {
    /// 0-based index into `PagerState.lines` this row belongs to.
    let bufferLine: Int
    /// Column within the buffer line where `text` begins (0 for chop mode and the
    /// first wrap segment; `k * width` for the k-th wrap segment). Lets matches be
    /// mapped onto the right row (#0010).
    let startColumn: Int
    /// The text of this row — a full buffer line (chop mode) or a width-wide
    /// wrapped segment (wrap mode).
    let text: String
}

/// A search match: a column range within one buffer line (#0010).
nonisolated struct SearchMatch: Equatable {
    let bufferLine: Int
    let start: Int   // column offset in the buffer line
    let length: Int
    var end: Int { start + length }
}

/// One visible row prepared for rendering: its text already windowed to the
/// viewport width, plus where that text starts in the buffer line so the view can
/// place search highlights (#0010).
nonisolated struct RenderRow: Equatable {
    let bufferLine: Int
    let startColumn: Int
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

    /// Whether the help overlay is showing (#0020).
    private(set) var showingHelp = false

    // MARK: - Search state (#0010 / #0011)

    /// The query being typed, while in search-input mode. `nil` when not typing.
    private(set) var searchInput: String?

    /// The most recently executed query ("" if none).
    private(set) var activeQuery = ""

    /// All matches for the active query, in (line, column) order.
    private(set) var matches: [SearchMatch] = []

    /// Index into `matches` of the current match (for n/N and the `match N/M` count).
    private(set) var currentMatchIndex = 0

    /// A transient status message (e.g. `no matches for "x"`, `last match`).
    private(set) var searchStatus: String?

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

    /// Shows or hides the help overlay (#0020). Scroll position is untouched, so
    /// closing help returns to exactly where the reader was.
    func setShowingHelp(_ showing: Bool) {
        guard showing != showingHelp else { return }
        objectWillChange.send()
        showingHelp = showing
    }

    // MARK: - Search (#0010 / #0011)

    /// True while the user is typing a query — the key handler routes input to it.
    var isSearching: Bool { searchInput != nil }

    /// True when there are active highlights / results to clear.
    var hasActiveSearch: Bool { !matches.isEmpty || searchStatus != nil || !activeQuery.isEmpty }

    /// The current match, if any (highlighted distinctly; #0011).
    var currentMatch: SearchMatch? {
        matches.indices.contains(currentMatchIndex) ? matches[currentMatchIndex] : nil
    }

    /// Matches that fall on a given buffer line, for highlighting (#0010).
    func matches(onBufferLine line: Int) -> [SearchMatch] {
        matches.filter { $0.bufferLine == line }
    }

    /// Enter search-input mode (`/`).
    func beginSearch() {
        objectWillChange.send()
        searchInput = ""
        searchStatus = nil
    }

    /// Append a typed character to the query.
    func appendSearchChar(_ character: Character) {
        guard searchInput != nil else { return }
        objectWillChange.send()
        searchInput?.append(character)
    }

    /// Backspace in the query; on an empty query this cancels search-input mode.
    func backspaceSearch() {
        guard let input = searchInput else { return }
        objectWillChange.send()
        if input.isEmpty {
            searchInput = nil
        } else {
            searchInput?.removeLast()
        }
    }

    /// Cancel search-input mode and clear any highlights (Esc while typing).
    func cancelSearch() {
        objectWillChange.send()
        searchInput = nil
        clearResults()
    }

    /// Clear active highlights/results without affecting input mode (Esc after a search).
    func clearSearch() {
        guard hasActiveSearch else { return }
        objectWillChange.send()
        clearResults()
    }

    /// Run the typed query: find all matches, jump to the first at/after the current
    /// top, and keep the highlights. Reports `no matches` when empty.
    func executeSearch() {
        guard let query = searchInput else { return }
        objectWillChange.send()
        searchInput = nil
        activeQuery = query
        guard !query.isEmpty else { clearResults(); return }
        matches = findMatches(query)
        guard !matches.isEmpty else {
            searchStatus = "no matches for \"\(query)\""
            currentMatchIndex = 0
            return
        }
        searchStatus = nil
        let topLine = currentTopBufferLine()
        currentMatchIndex = matches.firstIndex { $0.bufferLine >= topLine } ?? 0
        scrollToMatch(currentMatchIndex)
    }

    /// Advance to the next match (#0011). Clamps — no wrap — flashing `last match`
    /// at the end. The first `n` after a search continues from the match nearest the
    /// viewport (set by `executeSearch`); subsequent presses step by index.
    func nextMatch() {
        guard !matches.isEmpty else { return }
        if currentMatchIndex + 1 < matches.count {
            setCurrentMatch(currentMatchIndex + 1)
        } else {
            objectWillChange.send()
            searchStatus = "last match"
        }
    }

    /// Step back to the previous match (#0011). Clamps, flashing `first match`.
    func previousMatch() {
        guard !matches.isEmpty else { return }
        if currentMatchIndex > 0 {
            setCurrentMatch(currentMatchIndex - 1)
        } else {
            objectWillChange.send()
            searchStatus = "first match"
        }
    }

    private func setCurrentMatch(_ index: Int) {
        objectWillChange.send()
        currentMatchIndex = index
        searchStatus = nil
        scrollToMatch(index)
    }

    private func clearResults() {
        activeQuery = ""
        matches = []
        searchStatus = nil
        currentMatchIndex = 0
    }

    /// Scrolls so the display row holding `matches[index]` is at the top.
    private func scrollToMatch(_ index: Int) {
        guard matches.indices.contains(index) else { return }
        let match = matches[index]
        let rowIndex = displayRows.firstIndex { row in
            row.bufferLine == match.bufferLine
                && match.start >= row.startColumn
                && match.start < row.startColumn + max(1, row.text.count)
        } ?? displayRows.firstIndex { $0.bufferLine == match.bufferLine } ?? 0
        offset = clampedOffset(rowIndex)
    }

    private func findMatches(_ query: String) -> [SearchMatch] {
        guard !query.isEmpty else { return [] }
        var result: [SearchMatch] = []
        for (index, line) in lines.enumerated() {
            var searchStart = line.startIndex
            while searchStart < line.endIndex,
                  let range = line.range(of: query, options: .caseInsensitive, range: searchStart..<line.endIndex) {
                let start = line.distance(from: line.startIndex, to: range.lowerBound)
                let length = line.distance(from: range.lowerBound, to: range.upperBound)
                result.append(SearchMatch(bufferLine: index, start: start, length: length))
                searchStart = range.upperBound // non-overlapping matches
            }
        }
        return result
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

    /// The visible rows prepared for rendering: text already windowed to the viewport
    /// width, with the buffer line and start column so the view can place highlights.
    /// In wrap mode rows are width-wide segments; in chop mode the horizontal window
    /// `[horizontalOffset, +viewportWidth)` is applied.
    func visibleRenderRows() -> [RenderRow] {
        visibleDisplayRows().map { row in
            if wrapEnabled || viewportWidth <= 0 {
                return RenderRow(bufferLine: row.bufferLine, startColumn: row.startColumn, text: row.text)
            }
            return RenderRow(bufferLine: row.bufferLine, startColumn: horizontalOffset, text: horizontalWindow(row.text))
        }
    }

    /// The visible row texts, already windowed to the viewport width.
    func visibleLines() -> [String] {
        visibleRenderRows().map(\.text)
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
                var column = 0
                while start < line.endIndex {
                    let end = line.index(start, offsetBy: width, limitedBy: line.endIndex) ?? line.endIndex
                    rows.append(DisplayRow(bufferLine: index, startColumn: column, text: String(line[start..<end])))
                    column += width
                    start = end
                }
            } else {
                rows.append(DisplayRow(bufferLine: index, startColumn: 0, text: line))
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
