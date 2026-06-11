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

    private static let legend = "↑/↓ line · ⌥↑/⌥↓ page · Esc/q quit"
    private static let shortLegend = "↑/↓ ⌥↑/⌥↓ Esc/q"

    var body: some View {
        let width = state.viewportWidth
        let position = positionText
        // Reserve room for legend + a gap + position before showing the position.
        let showPosition = width == 0 || width >= Self.legend.count + position.count + 2
        let legendText = (width > 0 && width < Self.legend.count) ? Self.shortLegend : Self.legend

        return HStack(spacing: 1) {
            Text(legendText)
            Spacer()
            if showPosition {
                Text(position)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .foregroundColor(.brightWhite)
        .background(.blue)
    }

    /// Right-side position indicator: percentage (or `END` at the bottom) plus the
    /// last visible line number over the total.
    private var positionText: String {
        let bottomLine = min(state.offset + state.viewportHeight, state.lineCount)
        let progress = state.atEnd ? "END" : "\(state.positionPercent)%"
        return "\(progress) \(bottomLine)/\(state.lineCount)"
    }
}
