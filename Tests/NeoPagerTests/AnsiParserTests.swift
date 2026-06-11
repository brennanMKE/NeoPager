import Testing
@testable import NeoPager

@Suite struct AnsiParserTests {

    @Test func expandsTabsToEightColumnStops() {
        let (plain, runs, _) = AnsiParser.parseLine("a\tb", startStyle: .default)
        #expect(plain == "a       b") // 'a' at col 0, tab fills to col 8
        #expect(runs.isEmpty)
    }

    @Test func plainTextHasNoRuns() {
        let (plain, runs, end) = AnsiParser.parseLine("hello", startStyle: .default)
        #expect(plain == "hello")
        #expect(runs.isEmpty)
        #expect(end == .default)
    }

    @Test func stripsEscapesAndRecordsColorRun() {
        // The escape bytes are zero-width: plain text is just "red".
        let (plain, runs, end) = AnsiParser.parseLine("\u{1b}[31mred\u{1b}[0m", startStyle: .default)
        #expect(plain == "red")
        #expect(runs == [StyleRun(start: 0, length: 3, style: Style(foreground: .standard(1)))])
        #expect(end == .default) // reset by ESC[0m
    }

    @Test func resetEndsTheRunMidLine() {
        let (plain, runs, _) = AnsiParser.parseLine("\u{1b}[31mfoo\u{1b}[0mbar", startStyle: .default)
        #expect(plain == "foobar")
        #expect(runs == [StyleRun(start: 0, length: 3, style: Style(foreground: .standard(1)))])
    }

    @Test func colorCarriesAcrossLines() {
        let (plain, runs) = AnsiParser.parse(["\u{1b}[32mfoo", "bar"])
        #expect(plain == ["foo", "bar"])
        let green = Style(foreground: .standard(2))
        #expect(runs[0] == [StyleRun(start: 0, length: 3, style: green)])
        #expect(runs[1] == [StyleRun(start: 0, length: 3, style: green)]) // carried onto line 2
    }

    @Test func nonSGRControlSequencesAreStripped() {
        // ESC[2J (clear screen) must be removed, never executed or rendered.
        let (plain, runs, _) = AnsiParser.parseLine("\u{1b}[2Jfoo", startStyle: .default)
        #expect(plain == "foo")
        #expect(runs.isEmpty)
    }

    @Test func boldUnderlineInverse() {
        let (_, runs, _) = AnsiParser.parseLine("\u{1b}[1;4;7mX", startStyle: .default)
        #expect(runs == [StyleRun(start: 0, length: 1, style: Style(bold: true, underline: true, inverse: true))])
    }

    @Test func extended256AndTrueColor() {
        let (_, indexed, _) = AnsiParser.parseLine("\u{1b}[38;5;208mX", startStyle: .default)
        #expect(indexed.first?.style.foreground == .indexed(208))
        let (_, truecolor, _) = AnsiParser.parseLine("\u{1b}[48;2;10;20;30mX", startStyle: .default)
        #expect(truecolor.first?.style.background == .rgb(10, 20, 30))
    }

    @Test func brightForeground() {
        let (_, runs, _) = AnsiParser.parseLine("\u{1b}[91mX", startStyle: .default)
        #expect(runs.first?.style.foreground == .bright(1))
    }

    @Test func emptyParamsMeansReset() {
        // ESC[m with no parameters is a full reset.
        let (_, runs, end) = AnsiParser.parseLine("\u{1b}[31ma\u{1b}[mb", startStyle: .default)
        #expect(runs == [StyleRun(start: 0, length: 1, style: Style(foreground: .standard(1)))])
        #expect(end == .default)
    }
}
