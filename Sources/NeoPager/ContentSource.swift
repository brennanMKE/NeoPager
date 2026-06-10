import Foundation

/// Errors raised while loading pager content, before the TUI starts.
enum ContentError: Error {
    /// A file argument was given but could not be read.
    case fileNotReadable(path: String, reason: String)
    /// No file argument and stdin is an interactive terminal — there is nothing to page.
    case noInput
}

/// Loads all pager content up front into a line buffer, before the TUI starts.
///
/// Phase 1 reads everything eagerly (like `more`; `less` streams). Reading the
/// pipe fully to EOF here also means stdin is drained before #0003 rebinds
/// interactive input to `/dev/tty`. Streaming/incremental reading is a possible
/// later enhancement (noted in `PRD.md`), deliberately out of scope.
enum ContentSource {
    /// Reads content from `path` if given, otherwise from the stdin pipe.
    ///
    /// - Throws: `ContentError.noInput` when no file is given and stdin is a TTY;
    ///   `ContentError.fileNotReadable` when a given file cannot be read.
    nonisolated static func load(path: String?) throws -> [String] {
        if let path {
            return try loadFile(path)
        }
        // No file argument: only read stdin when it is a pipe/redirect, never an
        // interactive terminal — don't sit waiting on an empty TTY like `more`.
        guard isatty(STDIN_FILENO) == 0 else {
            throw ContentError.noInput
        }
        return loadPipe()
    }

    private nonisolated static func loadFile(_ path: String) throws -> [String] {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ContentError.fileNotReadable(path: path, reason: (error as NSError).localizedDescription)
        }
        return splitLines(decodeLossy(data))
    }

    private nonisolated static func loadPipe() -> [String] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return splitLines(decodeLossy(data))
    }

    /// Decodes bytes as UTF-8, substituting U+FFFD for invalid sequences rather
    /// than crashing — command output isn't guaranteed to be valid UTF-8.
    nonisolated static func decodeLossy(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Splits text into newline-delimited lines. A single trailing newline does
    /// not produce a spurious empty final line; CRLF carriage returns are stripped.
    nonisolated static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }
}
