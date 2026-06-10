import ArgumentParser
import Foundation

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

        // Placeholder until the viewport (#0005) lands: with no UI yet, a pager
        // is just `cat`. This proves both input modes load correctly.
        for line in lines {
            print(line)
        }
    }
}
