import SwiftTUI

/// The pager's root view: a viewport slice of the content with the status bar
/// pinned to the bottom row.
///
/// Only the visible lines are rendered (`PagerState.visibleLines()`), never the
/// whole buffer — content can be hundreds of thousands of lines. A `Spacer` fills
/// any unused height below short content so the status bar always sits on the
/// bottom row. Long lines are truncated to the terminal width (phase 1 policy;
/// refined in #0009).
struct PagerView: View {
    @ObservedObject var state: PagerState

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Text(row.text)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Spacer()
            StatusBar(state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The visible lines as identifiable rows. The id is the row's position within
    /// the viewport (0-based), so as the slice scrolls SwiftTUI updates each row's
    /// text in place rather than treating scrolled lines as inserts/removals.
    private var rows: [Row] {
        let width = state.viewportWidth
        return state.visibleLines().enumerated().map { offset, line in
            Row(id: offset, text: truncate(line, to: width))
        }
    }

    /// Truncates a line to `width` display columns. ASCII-accurate; wide characters,
    /// tabs, and ANSI escapes are handled in #0009 / #0012.
    private func truncate(_ line: String, to width: Int) -> String {
        guard width > 0, line.count > width else { return line }
        return String(line.prefix(width))
    }

    private struct Row: Identifiable {
        let id: Int
        let text: String
    }
}
