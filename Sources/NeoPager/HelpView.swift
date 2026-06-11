import SwiftTUI

/// Full-screen help overlay (#0020) listing every key binding. Shown while
/// `PagerState.showingHelp` is true; any key dismisses it (handled in the key
/// handler). The reader's scroll position is preserved underneath.
struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NeoPager — key bindings").bold()
            Text("")
            ForEach(Self.bindings) { binding in
                Text(Self.row(binding.keys, binding.description))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Text("")
            Text("Press any key to close").foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private struct Binding: Identifiable {
        let id: Int
        let keys: String
        let description: String
    }

    private static let bindings: [Binding] = [
        Binding(id: 0, keys: "↑ / ↓",                  description: "scroll one line"),
        Binding(id: 1, keys: "⌥↑ / ⌥↓ · PgUp / PgDn",  description: "scroll one page"),
        Binding(id: 2, keys: "Space / b",              description: "page down / up"),
        Binding(id: 3, keys: "d / u",                  description: "half page down / up"),
        Binding(id: 4, keys: "g / G · Home / End",     description: "jump to top / bottom"),
        Binding(id: 5, keys: "← / →",                  description: "scroll sideways (chop mode, -S)"),
        Binding(id: 6, keys: "h / F1",                 description: "toggle this help"),
        Binding(id: 7, keys: "Esc / q",                description: "quit"),
    ]

    /// Pads the key column to a fixed width so the descriptions line up.
    private static func row(_ keys: String, _ description: String) -> String {
        let column = 26
        let pad = max(1, column - keys.count)
        return "  " + keys + String(repeating: " ", count: pad) + description
    }
}
