import Combine

/// Observable scroll model for the pager.
///
/// Pure logic — no SwiftTUI imports — so the clamp/boundary behavior is testable
/// without a terminal. SwiftTUI views observe it through Combine `ObservableObject`
/// (`objectWillChange`), which is what triggers a re-render when the offset moves.
nonisolated final class PagerState: ObservableObject {
    /// The full content buffer, loaded up front. Immutable for the pager's lifetime.
    let lines: [String]

    /// Number of content rows visible at once (terminal height minus the status bar).
    private(set) var viewportHeight: Int

    /// Index of the first visible line (0-based). Always within `0 ... maxOffset`.
    private(set) var offset: Int = 0

    let objectWillChange = ObservableObjectPublisher()

    init(lines: [String], viewportHeight: Int = 0) {
        self.lines = lines
        self.viewportHeight = max(0, viewportHeight)
    }

    var lineCount: Int { lines.count }

    /// Largest valid offset — the last line sits at the bottom of the viewport.
    /// Zero when all content fits, so there is nothing to scroll.
    var maxOffset: Int { max(0, lineCount - viewportHeight) }

    /// True when the last line is visible (including when all content fits in the
    /// viewport). The status bar surfaces this as `END`.
    var atEnd: Bool { offset >= maxOffset }

    /// True when the first line is visible.
    var atTop: Bool { offset <= 0 }

    /// Scroll progress as a whole percentage — 0 at the top, 100 at the bottom
    /// clamp (and 100 when all content fits, since the end is already on screen).
    var positionPercent: Int {
        guard maxOffset > 0 else { return 100 }
        return Int((Double(offset) / Double(maxOffset) * 100).rounded())
    }

    // MARK: - Movement

    /// Scroll up one line. No-op (no wrap, no bell, no exit) when already at the top.
    func lineUp() { setOffset(offset - 1) }

    /// Scroll down one line. No-op when already at the bottom — crucially, reaching
    /// the bottom never exits the pager (the original sin of `more`).
    func lineDown() { setOffset(offset + 1) }

    /// Scroll up one full viewport. Clamps at the top.
    func pageUp() { setOffset(offset - viewportHeight) }

    /// Scroll down one full viewport. Clamps at the bottom.
    func pageDown() { setOffset(offset + viewportHeight) }

    /// Updates the viewport height (e.g. on terminal resize) and re-clamps the
    /// offset so the view stays valid — shrinking near the bottom must not leave
    /// blank rows below the last line.
    func setViewportHeight(_ height: Int) {
        let newHeight = max(0, height)
        let newOffset = min(offset, max(0, lineCount - newHeight))
        guard newHeight != viewportHeight || newOffset != offset else { return }
        objectWillChange.send()
        viewportHeight = newHeight
        offset = newOffset
    }

    /// The slice of lines currently visible, top-aligned. Safe for any offset and
    /// any viewport size; returns an empty slice when there is nothing to show.
    func visibleLines() -> ArraySlice<String> {
        guard viewportHeight > 0, !lines.isEmpty else { return [] }
        let end = min(offset + viewportHeight, lineCount)
        let start = min(offset, end)
        return lines[start..<end]
    }

    private func setOffset(_ newValue: Int) {
        let clamped = min(max(0, newValue), maxOffset)
        // No-op past either end: don't emit a change, so the view doesn't repaint.
        guard clamped != offset else { return }
        objectWillChange.send()
        offset = clamped
    }
}
