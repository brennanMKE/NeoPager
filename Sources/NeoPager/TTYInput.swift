import Foundation

/// Rebinds interactive keyboard input to the controlling terminal.
///
/// In `cmd | neopager`, fd 0 is the pipe, not the keyboard. After `ContentSource`
/// drains that pipe to EOF, SwiftTUI would otherwise read key events from an
/// exhausted pipe and the pager would be uncontrollable. Opening `/dev/tty` and
/// `dup2`-ing it onto fd 0 — before `Application.start()` installs its input source
/// — points keyboard input back at the terminal. This is what `less` does.
///
/// The mechanism was proven in a controlling-tty spike: after draining a piped
/// fd 0, `FileHandle.standardInput.availableData` (the exact call SwiftTUI's
/// `handleInput` makes) reads keystrokes from the tty once fd 0 is redirected.
enum TTYInput {
    /// Reattaches keyboard input to `/dev/tty` when stdin is not already a terminal.
    /// No-op (and returns `true`) when stdin is already interactive — the
    /// `neopager file.txt` case, where fd 0 is the keyboard to begin with.
    ///
    /// - Returns: `true` on success (or no-op), `false` if `/dev/tty` could not be
    ///   opened or redirected.
    @discardableResult
    nonisolated static func reattachToControllingTerminal() -> Bool {
        guard isatty(STDIN_FILENO) == 0 else { return true }
        let ttyfd = open("/dev/tty", O_RDONLY)
        guard ttyfd >= 0 else { return false }
        let ok = dup2(ttyfd, STDIN_FILENO) >= 0
        if ttyfd != STDIN_FILENO { close(ttyfd) }
        return ok
    }
}

/// Queries the current terminal size.
enum TerminalSize {
    /// The terminal's `(rows, columns)` via `TIOCGWINSZ`, or `nil` if unavailable
    /// (e.g. output is not a terminal).
    nonisolated static func current() -> (rows: Int, columns: Int)? {
        var ws = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0,
              ws.ws_row > 0, ws.ws_col > 0 else {
            return nil
        }
        return (rows: Int(ws.ws_row), columns: Int(ws.ws_col))
    }
}
