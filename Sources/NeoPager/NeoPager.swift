import ArgumentParser
import Foundation
import SwiftTUI

@main
struct NeoPager: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "neopager",
        abstract: "A modern terminal pager with a persistent key legend that never auto-exits at the bottom."
    )

    @Argument(help: "File to page. If omitted, content is read from a stdin pipe.")
    var file: String?

    @Flag(name: [.customShort("S"), .customLong("chop-long-lines")],
          help: "Chop long lines at the right edge instead of wrapping them.")
    var chopLongLines = false

    mutating func run() throws {
        let lines: [String]
        do {
            lines = try ContentSource.load(path: file)
        } catch ContentError.noInput {
            throw ValidationError(
                "No input. Pipe output in or pass a file:\n  some-command | neopager\n  neopager file.txt"
            )
        } catch let ContentError.fileNotReadable(path, reason) {
            FileHandle.standardError.write(Data("neopager: \(path): \(reason)\n".utf8))
            throw ExitCode.failure
        }

        // Size the viewport from the terminal (status bar reserves one row).
        let size = TerminalSize.current() ?? (rows: 24, columns: 80)
        let viewportHeight = max(1, size.rows - 1)
        let state = PagerState(
            lines: lines,
            viewportHeight: viewportHeight,
            viewportWidth: size.columns,
            wrapEnabled: !chopLongLines   // wrap by default; -S chops (#0019)
        )

        // #0018: if all the content fits on one screen, don't take over the terminal
        // — print it and exit (like less -F). rowCount is wrap/chop-aware, and the
        // full terminal height is available since there's no status bar in this path.
        if state.rowCount <= size.rows {
            for line in lines { print(line) }
            return
        }

        // Rebind keyboard input to the controlling terminal before SwiftTUI takes
        // over stdin — in `cmd | neopager`, fd 0 is the now-drained pipe (#0003).
        TTYInput.reattachToControllingTerminal()

        // ArgumentParser calls run() on the main thread, so assumeIsolated is safe.
        MainActor.assumeIsolated {
            let app = Application(rootView: PagerView(state: state))
            app.keyHandler = { [weak app] event in
                // While help is showing it's modal: any key closes it and does
                // nothing else (#0020).
                if state.showingHelp {
                    state.setShowingHelp(false)
                    return
                }
                // Search-input mode is modal (#0010): keys edit the query, and the
                // pager's normal bindings (q, b, Space, …) are literal characters.
                if state.isSearching {
                    switch event {
                    case .char(let character): state.appendSearchChar(character)
                    case .backspace:           state.backspaceSearch()
                    case .enter:               state.executeSearch()
                    case .escape:              state.cancelSearch()
                    default:                   break
                    }
                    return
                }
                switch event {
                case .up:       state.lineUp()
                case .down:     state.lineDown()
                case .pageUp:   state.pageUp()
                case .pageDown: state.pageDown()
                case .home:     state.scrollToTop()    // #0015 Home -> top
                case .end:      state.scrollToBottom() // #0015 End -> bottom
                case .left:     state.scrollLeft()     // #0016 horizontal scroll (chop mode)
                case .right:    state.scrollRight()    // #0016 horizontal scroll (chop mode)
                case .f1:       state.setShowingHelp(true) // #0020 F1 opens help
                case .escape:
                    // First Esc clears active highlights; a second Esc exits (#0010).
                    if state.hasActiveSearch { state.clearSearch() }
                    else { app?.quit() }
                case .char(let character):
                    switch character {
                    case " ":         state.pageDown()           // #0014 Space pages down
                    case "b", "B":    state.pageUp()             // #0014 b pages up (less convention)
                    case "d":         state.halfPageDown()       // #0017 half-page down
                    case "u":         state.halfPageUp()         // #0017 half-page up
                    case "g":         state.scrollToTop()        // #0015 g -> top
                    case "G":         state.scrollToBottom()     // #0015 G -> bottom
                    case "h":         state.setShowingHelp(true) // #0020 h opens help
                    case "/":         state.beginSearch()        // #0010 enter search
                    case "n":         state.nextMatch()          // #0011 next match
                    case "N":         state.previousMatch()      // #0011 previous match
                    case "q", "Q":    app?.quit()                // #0013 q quits, like Esc
                    default:          break
                    }
                case .enter, .backspace:
                    break // unused in phase 1
                }
            }

            // Recompute the viewport on terminal resize (#0009). SwiftTUI re-lays
            // out its own layer on SIGWINCH, but only PagerState knows the pager's
            // height/width and offset, so it needs its own observer. Held for the
            // process lifetime (start() never returns).
            let resizeSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
            resizeSource.setEventHandler {
                guard let size = TerminalSize.current() else { return }
                state.setViewport(height: max(1, size.rows - 1), width: size.columns)
            }
            resizeSource.resume()
            withExtendedLifetime(resizeSource) {
                app.start() // calls dispatchMain(); never returns
            }
        }
    }
}
