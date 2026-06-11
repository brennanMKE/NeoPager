import Foundation

/// A terminal color, kept independent of SwiftTUI so the model stays UI-free and
/// testable. The view maps these onto SwiftTUI colors (#0012).
nonisolated enum AnsiColor: Equatable {
    case `default`
    case standard(Int)      // 0...7  (the 8 base ANSI colors)
    case bright(Int)        // 0...7  (the 8 bright variants)
    case indexed(Int)       // 0...255 (the 256-color palette)
    case rgb(Int, Int, Int) // 24-bit true color
}

/// A run of text style produced by SGR sequences.
nonisolated struct Style: Equatable {
    var foreground: AnsiColor = .default
    var background: AnsiColor = .default
    var bold = false
    var underline = false
    var inverse = false

    static let `default` = Style()
}

/// A maximal run of columns within a plain (escape-free, tab-expanded) buffer line
/// that share one style. Only non-default runs are emitted.
nonisolated struct StyleRun: Equatable {
    let start: Int   // 0-based column in the plain line
    let length: Int
    let style: Style
}

/// Parses ANSI/SGR escape sequences out of raw content into plain text plus per-line
/// style runs (#0012). Escapes are removed from the text (so wrap/chop/truncate column
/// math stays correct — escapes are zero-width), tabs are expanded here (column-aware,
/// after escapes are stripped), SGR sequences become styles, and any non-SGR control
/// sequence is stripped and never executed. Style carries across line boundaries.
nonisolated enum AnsiParser {
    /// Parses all lines, threading the SGR state across line boundaries so a color
    /// opened on one line still applies on later lines until reset.
    static func parse(_ rawLines: [String], tabWidth: Int = 8) -> (plain: [String], runs: [[StyleRun]]) {
        var style = Style.default
        var plainLines: [String] = []
        var runLines: [[StyleRun]] = []
        plainLines.reserveCapacity(rawLines.count)
        runLines.reserveCapacity(rawLines.count)
        for line in rawLines {
            let (text, runs, endStyle) = parseLine(line, startStyle: style, tabWidth: tabWidth)
            plainLines.append(text)
            runLines.append(runs)
            style = endStyle
        }
        return (plainLines, runLines)
    }

    /// Parses one raw line. Returns the plain text, its non-default style runs, and the
    /// style in effect at end of line (to carry into the next line).
    static func parseLine(_ line: String, startStyle: Style, tabWidth: Int = 8) -> (String, [StyleRun], Style) {
        let chars = Array(line)
        var style = startStyle
        var plain = ""
        var runs: [StyleRun] = []
        var column = 0
        var runStart = 0
        var runStyle = startStyle
        var i = 0

        func closeRun() {
            if column > runStart, runStyle != .default {
                runs.append(StyleRun(start: runStart, length: column - runStart, style: runStyle))
            }
            runStart = column
            runStyle = style
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\u{1b}" {
                if i + 1 < chars.count, chars[i + 1] == "[" {
                    // CSI: parameter bytes 0x30–0x3F, intermediates 0x20–0x2F, final 0x40–0x7E.
                    var j = i + 2
                    var params = ""
                    while j < chars.count, let v = chars[j].unicodeScalars.first?.value, (0x30...0x3F).contains(v) {
                        params.append(chars[j]); j += 1
                    }
                    while j < chars.count, let v = chars[j].unicodeScalars.first?.value, (0x20...0x2F).contains(v) {
                        j += 1
                    }
                    if j < chars.count {
                        if chars[j] == "m" { // SGR — the only sequence we apply
                            closeRun()
                            style = applySGR(params, to: style)
                            runStyle = style
                        }
                        // Any other final byte: a non-SGR control sequence — strip it.
                        i = j + 1
                    } else {
                        i = chars.count // incomplete sequence at EOL — drop the rest
                    }
                } else {
                    // ESC not starting a CSI (e.g. charset selection): drop ESC + next byte.
                    i += (i + 1 < chars.count) ? 2 : 1
                }
            } else if c == "\t" {
                let spaces = tabWidth - (column % tabWidth)
                plain += String(repeating: " ", count: spaces)
                column += spaces
                i += 1
            } else {
                plain.append(c)
                column += 1
                i += 1
            }
        }
        closeRun()
        return (plain, runs, style)
    }

    /// Applies an SGR parameter string (e.g. "1;31" or "38;5;208") to a style.
    static func applySGR(_ params: String, to start: Style) -> Style {
        var style = start
        // An empty parameter string (ESC[m) means reset.
        let codes = params.isEmpty ? [0] : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var k = 0
        while k < codes.count {
            let code = codes[k]
            switch code {
            case 0:  style = .default
            case 1:  style.bold = true
            case 4:  style.underline = true
            case 7:  style.inverse = true
            case 22: style.bold = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .standard(code - 30)
            case 39: style.foreground = .default
            case 40...47: style.background = .standard(code - 40)
            case 49: style.background = .default
            case 90...97: style.foreground = .bright(code - 90)
            case 100...107: style.background = .bright(code - 100)
            case 38, 48:
                // Extended color: 38;5;n / 48;5;n (indexed) or 38;2;r;g;b / 48;2;r;g;b.
                let isForeground = (code == 38)
                if k + 1 < codes.count, codes[k + 1] == 5, k + 2 < codes.count {
                    let color = AnsiColor.indexed(codes[k + 2])
                    if isForeground { style.foreground = color } else { style.background = color }
                    k += 2
                } else if k + 1 < codes.count, codes[k + 1] == 2, k + 4 < codes.count {
                    let color = AnsiColor.rgb(codes[k + 2], codes[k + 3], codes[k + 4])
                    if isForeground { style.foreground = color } else { style.background = color }
                    k += 4
                }
            default:
                break // unsupported SGR code — ignore
            }
            k += 1
        }
        return style
    }
}
