import SwiftTUI

/// The pager's root view: a viewport slice of the content with the status bar
/// pinned to the bottom row.
///
/// Only the visible rows are rendered (`PagerState.visibleRenderRows()`), never the
/// whole buffer. A `Spacer` fills any unused height below short content so the
/// status bar always sits on the bottom row. Each row's text is windowed to the
/// viewport width; ANSI colors (#0012) and search highlights (#0010/#0011) are
/// composed into styled spans within the row.
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

    private func styled(_ span: Span) -> some View {
        let resolved = resolve(span)
        return Text(span.text)
            .foregroundColor(resolved.foreground)
            .background(resolved.background)
            .boldIf(resolved.bold)
            .underlineIf(resolved.underline)
    }

    /// Splits a row's text into spans of constant (content style, search highlight),
    /// merging the ANSI style runs (#0012) with the active search matches
    /// (#0010/#0011) at the column level.
    private func spans(for row: RenderRow) -> [Span] {
        let chars = Array(row.text)
        let n = chars.count
        guard n > 0 else { return [Span(id: 0, text: "", style: .default, highlight: .none)] }

        var styles = [Style](repeating: .default, count: n)
        var highlights = [Highlight](repeating: .none, count: n)

        for run in state.styleRuns(onBufferLine: row.bufferLine) {
            let lo = Swift.max(0, run.start - row.startColumn)
            let hi = Swift.min(n, run.start + run.length - row.startColumn)
            var c = lo
            while c < hi { styles[c] = run.style; c += 1 }
        }

        let current = state.currentMatch
        for match in state.matches(onBufferLine: row.bufferLine) {
            let lo = Swift.max(0, match.start - row.startColumn)
            let hi = Swift.min(n, match.end - row.startColumn)
            let kind: Highlight = (match == current) ? .current : .match
            var c = lo
            while c < hi { highlights[c] = kind; c += 1 }
        }

        var spans: [Span] = []
        var id = 0
        var i = 0
        while i < n {
            let style = styles[i]
            let highlight = highlights[i]
            var j = i + 1
            while j < n, styles[j] == style, highlights[j] == highlight { j += 1 }
            spans.append(Span(id: id, text: String(chars[i..<j]), style: style, highlight: highlight))
            id += 1
            i = j
        }
        return spans
    }

    /// Resolves a span's content style + search highlight into concrete SwiftTUI
    /// colors and flags, applying inverse and letting the highlight override the
    /// background so matches stand out over colored content.
    private func resolve(_ span: Span) -> (foreground: Color, background: Color, bold: Bool, underline: Bool) {
        var fg = Self.color(span.style.foreground)
        var bg = Self.color(span.style.background)
        if span.style.inverse {
            swap(&fg, &bg)
            fg = fg ?? .black
            bg = bg ?? .white
        }
        switch span.highlight {
        case .none:
            break
        case .match:
            bg = .brightBlack
            fg = fg ?? .brightWhite
        case .current:
            bg = .yellow
            fg = .black
        }
        return (fg ?? .default, bg ?? .default, span.style.bold, span.style.underline)
    }

    private static func color(_ ansi: AnsiColor) -> Color? {
        switch ansi {
        case .default:           return nil
        case .standard(let n):   return standardColors[safe: n]
        case .bright(let n):     return brightColors[safe: n]
        case .indexed(let n):    return indexedColor(n)
        case .rgb(let r, let g, let b): return .trueColor(red: r, green: g, blue: b)
        }
    }

    private static let standardColors: [Color] = [.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white]
    private static let brightColors: [Color] = [.brightBlack, .brightRed, .brightGreen, .brightYellow, .brightBlue, .brightMagenta, .brightCyan, .brightWhite]

    /// Maps a 256-color palette index to a concrete color (named for 0–15, the 6×6×6
    /// cube for 16–231, grayscale ramp for 232–255).
    private static func indexedColor(_ n: Int) -> Color {
        if n < 8 { return standardColors[n] }
        if n < 16 { return brightColors[n - 8] }
        if n < 232 {
            let i = n - 16
            func level(_ x: Int) -> Int { x == 0 ? 0 : 55 + x * 40 }
            return .trueColor(red: level((i / 36) % 6), green: level((i / 6) % 6), blue: level(i % 6))
        }
        let gray = 8 + (n - 232) * 10
        return .trueColor(red: gray, green: gray, blue: gray)
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
        let style: Style
        let highlight: Highlight
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension View {
    @ViewBuilder func boldIf(_ on: Bool) -> some View {
        if on { self.bold() } else { self }
    }

    @ViewBuilder func underlineIf(_ on: Bool) -> some View {
        if on { self.underline() } else { self }
    }
}
