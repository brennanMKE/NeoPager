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
        let state = PagerState(lines: lines, viewportHeight: viewportHeight)
        state.setViewport(height: viewportHeight, width: size.columns)

        // Rebind keyboard input to the controlling terminal before SwiftTUI takes
        // over stdin — in `cmd | neopager`, fd 0 is the now-drained pipe (#0003).
        TTYInput.reattachToControllingTerminal()

        // ArgumentParser calls run() on the main thread, so assumeIsolated is safe.
        MainActor.assumeIsolated {
            let app = Application(rootView: PagerView(state: state))
            app.keyHandler = { [weak app] event in
                switch event {
                case .up:       state.lineUp()
                case .down:     state.lineDown()
                case .pageUp:   state.pageUp()
                case .pageDown: state.pageDown()
                case .escape:   app?.quit()
                case .char(let character):
                    switch character {
                    case " ":         state.pageDown()  // #0014 Space pages down
                    case "b", "B":    state.pageUp()    // #0014 b pages up (less convention)
                    case "q", "Q":    app?.quit()       // #0013 q quits, like Esc
                    default:          break             // other chars: search input (phase 2)
                    }
                case .left, .right, .enter, .backspace:
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
