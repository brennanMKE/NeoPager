import SwiftTUI

/// The pager's root view: a viewport slice of the content with the status bar
/// pinned to the bottom row.
///
/// Only the visible rows are rendered (`PagerState.visibleRenderRows()`), never the
/// whole buffer. A `Spacer` fills any unused height below short content so the
/// status bar always sits on the bottom row. Each row's text is already windowed to
/// the viewport width (wrap segments / chop horizontal window), and search matches
/// (#0010/#0011) are highlighted as styled spans within the row.
struct PagerView: View {
    @ObservedObject var state: PagerState

    var body: some View {
        if state.showingHelp {
            HelpView()
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    rowView(row)
                }
                Spacer()
                StatusBar(state: state)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The visible rows, keyed by viewport position (0-based) so SwiftTUI updates
    /// each row's content in place as the slice scrolls.
    private var rows: [IndexedRow] {
        state.visibleRenderRows().enumerated().map { IndexedRow(id: $0.offset, row: $0.element) }
    }

    private func rowView(_ indexed: IndexedRow) -> some View {
        HStack(spacing: 0) {
            ForEach(spans(for: indexed.row)) { span in
                styled(span)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func styled(_ span: Span) -> some View {
        if span.highlight == .current {
            Text(span.text).foregroundColor(.black).background(.yellow)
        } else if span.highlight == .match {
            Text(span.text).foregroundColor(.brightWhite).background(.brightBlack)
        } else {
            Text(span.text)
        }
    }

    /// Splits a row's text into highlighted / normal spans based on the active
    /// search matches that fall within this row's column window.
    private func spans(for row: RenderRow) -> [Span] {
        let rowStart = row.startColumn
        let rowEnd = rowStart + row.text.count
        let current = state.currentMatch
        // Matches intersected with this row's window, as (start, end) offsets into row.text.
        let hits = state.matches(onBufferLine: row.bufferLine).compactMap { match -> (Int, Int, Highlight)? in
            let start = Swift.max(match.start, rowStart)
            let end = Swift.min(match.end, rowEnd)
            guard start < end else { return nil }
            return (start - rowStart, end - rowStart, match == current ? .current : .match)
        }.sorted { $0.0 < $1.0 }

        guard !hits.isEmpty else { return [Span(id: 0, text: row.text, highlight: .none)] }

        let chars = Array(row.text)
        var spans: [Span] = []
        var cursor = 0
        var id = 0
        for (start, end, kind) in hits {
            let s = Swift.min(Swift.max(start, cursor), chars.count)
            let e = Swift.min(end, chars.count)
            if s > cursor {
                spans.append(Span(id: id, text: String(chars[cursor..<s]), highlight: .none)); id += 1
            }
            if s < e {
                spans.append(Span(id: id, text: String(chars[s..<e]), highlight: kind)); id += 1
                cursor = e
            }
        }
        if cursor < chars.count {
            spans.append(Span(id: id, text: String(chars[cursor...]), highlight: .none))
        }
        return spans
    }

    private struct IndexedRow: Identifiable {
        let id: Int
        let row: RenderRow
    }

    private enum Highlight {
        case none, match, current
    }

    private struct Span: Identifiable {
        let id: Int
        let text: String
        let highlight: Highlight
    }
}
