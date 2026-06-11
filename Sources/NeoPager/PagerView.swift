import SwiftTUI

/// The pager's root view: a viewport slice of the content with the status bar
/// pinned to the bottom row.
///
/// Only the visible lines are rendered (`PagerState.visibleLines()`), never the
/// whole buffer — content can be hundreds of thousands of lines. A `Spacer` fills
/// any unused height below short content so the status bar always sits on the
/// bottom row. `visibleLines()` already windows each row to the viewport width —
/// wrap segments fit by construction, and chop-mode rows are sliced to the current
/// horizontal offset (#0016) — so the view renders them directly.
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
        state.visibleLines().enumerated().map { offset, line in
            Row(id: offset, text: line)
        }
    }

    private struct Row: Identifiable {
        let id: Int
        let text: String
    }
}
