import SwiftTUI

/// The persistent bottom status bar — the feature that distinguishes NeoPager
/// from `more`/`less`. One row, visually distinct (inverted/colored), always
/// showing the movement keys on the left and the position on the right.
///
/// On narrow terminals it degrades gracefully: drop the position first, then fall
/// back to a shortened legend, rather than wrapping to a second row (which would
/// break the viewport height math).
struct StatusBar: View {
    @ObservedObject var state: PagerState

    private static let legend = "↑/↓ line · ⌥↑/⌥↓ page · Esc quit"
    private static let shortLegend = "↑/↓ ⌥↑/⌥↓ Esc"

    var body: some View {
        // While typing a query, the bar becomes the search input (#0010).
        if let input = state.searchInput {
            return barRow(left: "/" + input, right: "")
        }
        // A transient search message (no matches / first/last match) takes the bar.
        if let message = state.searchStatus {
            return barRow(left: message, right: positionText)
        }

        let width = state.viewportWidth
        let right = state.matches.isEmpty ? positionText : "match \(matchOrdinal) · \(positionText)"
        // Reserve room for legend + a gap + the right side before showing it.
        let showRight = width == 0 || width >= Self.legend.count + right.count + 2
        let legendText = (width > 0 && width < Self.legend.count) ? Self.shortLegend : Self.legend
        return barRow(left: legendText, right: showRight ? right : "")
    }

    private func barRow(left: String, right: String) -> some View {
        HStack(spacing: 1) {
            Text(left)
            Spacer()
            if !right.isEmpty {
                Text(right)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .foregroundColor(.brightWhite)
        .background(.blue)
    }

    /// `3/17` — the current match position within the match list (#0011).
    private var matchOrdinal: String {
        "\(state.currentMatchIndex + 1)/\(state.matches.count)"
    }

    /// Right-side position indicator: percentage (or `END` at the bottom) plus the
    /// last visible line number over the total.
    private var positionText: String {
        let progress = state.atEnd ? "END" : "\(state.positionPercent)%"
        return "\(progress) \(state.bottomBufferLine)/\(state.lineCount)"
    }
}
