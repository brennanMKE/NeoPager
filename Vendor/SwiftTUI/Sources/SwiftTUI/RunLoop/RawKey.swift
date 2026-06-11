import Foundation

// NeoPager patch: raw key events.
//
// Upstream SwiftTUI decodes only bare arrow keys and routes them to focus
// movement (see ArrowKeyParser + Application.handleInput). Apps that need a
// raw-key interaction model — plain arrows, Option/Meta arrows, Page keys, a
// bare Esc, and printable characters — have no way in. This file adds a public
// key-event type and a chunk parser; `Application.keyHandler` (see Application.swift)
// opts an app into receiving these instead of focus handling.

/// A decoded key event delivered to `Application.keyHandler`.
public enum RawKeyEvent: Equatable {
    case up, down, left, right
    case pageUp, pageDown
    case home, end
    case escape
    case enter
    case backspace
    /// A printable character (used for e.g. search input).
    case char(Character)
}

/// Decodes a chunk of terminal input bytes into discrete key events.
///
/// SwiftTUI reads input a chunk at a time (`FileHandle.availableData`). Terminals
/// deliver a full escape sequence in a single chunk, and a bare Esc press arrives
/// as a lone `ESC` byte, so the bare-Esc/escape-sequence ambiguity can be resolved
/// by looking at the whole chunk without a read timeout. (A lone `ESC` immediately
/// followed in the same chunk by an unrelated key — rare, e.g. a fast Meta combo —
/// is treated as Esc; this is acceptable for a pager whose Esc is the quit key.)
public enum RawKeyParser {
    public static func parse(_ string: String) -> [RawKeyEvent] {
        let ch = Array(string)
        var events: [RawKeyEvent] = []
        var i = 0
        while i < ch.count {
            let c = ch[i]
            switch c {
            case "\u{1b}": // ESC — possibly the start of a sequence
                let (event, consumed) = parseEscape(ch, i)
                if let event { events.append(event) }
                i += consumed
            case "\r", "\n":
                events.append(.enter); i += 1
            case "\u{7f}", "\u{08}":
                events.append(.backspace); i += 1
            default:
                // Skip other C0 control bytes; pass printable characters through.
                if let scalar = c.unicodeScalars.first, scalar.value < 0x20 {
                    i += 1
                } else {
                    events.append(.char(c)); i += 1
                }
            }
        }
        return events
    }

    /// Parses an escape sequence starting at `i` (where `ch[i] == ESC`).
    /// Returns the event (or nil for an unrecognized/incomplete sequence) and the
    /// number of characters consumed.
    private static func parseEscape(_ ch: [Character], _ i: Int) -> (RawKeyEvent?, Int) {
        let n = ch.count
        // Lone ESC at the end of the chunk → bare Escape.
        guard i + 1 < n else { return (.escape, 1) }
        let c1 = ch[i + 1]

        // `ESC ESC [ A/B` — the Meta/Option-arrow variant some terminals send.
        if c1 == "\u{1b}" {
            if i + 3 < n, ch[i + 2] == "[" {
                switch ch[i + 3] {
                case "A": return (.pageUp, 4)
                case "B": return (.pageDown, 4)
                default: break
                }
            }
            // `ESC ESC <other>`: treat the first ESC as a bare Escape.
            return (.escape, 1)
        }

        // CSI (`ESC [ …`) or SS3 application-cursor mode (`ESC O …`).
        if c1 == "[" || c1 == "O" {
            var j = i + 2
            var params = ""
            while j < n {
                let cj = ch[j]
                if cj.isLetter || cj == "~" { // final byte
                    return (csiEvent(prefix: c1, params: params, final: cj), j - i + 1)
                }
                params.append(cj)
                j += 1
            }
            // Incomplete sequence in this chunk — consume it, emit nothing.
            return (nil, n - i)
        }

        // ESC followed by an ordinary character (unsupported Meta combo): treat
        // the ESC as a bare Escape and let the next character parse on its own.
        return (.escape, 1)
    }

    private static func csiEvent(prefix: Character, params: String, final: Character) -> RawKeyEvent? {
        // SS3: application-cursor-mode arrows (`ESC O A` etc.).
        if prefix == "O" {
            switch final {
            case "A": return .up
            case "B": return .down
            case "C": return .right
            case "D": return .left
            case "H": return .home
            case "F": return .end
            default: return nil
            }
        }
        // CSI. `1;3` is the xterm Option/Alt modifier → page movement; other
        // modifiers (Ctrl `1;5`, Shift `1;2`) fall through to plain line movement.
        switch final {
        case "A": return params == "1;3" ? .pageUp : .up
        case "B": return params == "1;3" ? .pageDown : .down
        case "C": return .right
        case "D": return .left
        case "H": return .home   // CSI H (often unparameterized Home)
        case "F": return .end    // CSI F (End)
        case "~":
            switch params {
            case "1", "7": return .home    // Home (vt220 / rxvt forms)
            case "4", "8": return .end     // End
            case "5": return .pageUp       // Page Up
            case "6": return .pageDown     // Page Down
            default: return nil
            }
        default:
            return nil
        }
    }
}
