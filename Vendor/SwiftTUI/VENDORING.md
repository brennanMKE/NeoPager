# Vendored SwiftTUI

This is a local, patched copy of [SwiftTUI](https://github.com/rensbreur/SwiftTUI)
(MIT, © 2022 Rens Breur — see `LICENSE`).

- **Upstream:** https://github.com/rensbreur/SwiftTUI
- **Pinned revision:** `537133031bc2b2731048d00748c69700e1b48185` (branch `main`)

## Why vendored

NeoPager's whole interaction model is raw keys — `↑`/`↓` scroll a line, `⌥↑`/`⌥↓`
scroll a page, `Esc` quits. Upstream SwiftTUI cannot deliver these:

- `Application.handleInput` hardcodes arrow keys to move focus between Buttons and
  never delivers them to views; bare `Esc` is swallowed; Option-arrows and Page
  keys are not parsed.
- There is no public hook to intercept key events, and the render primitives
  (`Window`, `Renderer`, `Node`, `Control`) are `internal`, so a downstream module
  cannot drive its own run loop either.

Carrying a patched copy is the option chosen for this project (over a GitHub fork).

## Local patches

Each patch is marked in-source with a `// NeoPager patch:` comment.

- **Raw key events (#0004).**
  - `RunLoop/RawKey.swift` (new): `RawKeyEvent` enum + `RawKeyParser` chunk decoder
    for arrows, Option/Meta-arrows, Page Up/Down, bare Esc, Enter, Backspace, and
    printable characters.
  - `RunLoop/Application.swift`: added `public var keyHandler: ((RawKeyEvent) -> Void)?`;
    `handleInput` routes the whole chunk through `RawKeyParser` to that handler when
    set, bypassing focus-based key handling; added `public func quit()` exposing the
    private `stop()` for a clean Esc-driven shutdown.

## Trimmed from upstream

- Dropped the `swift-docc-plugin` package dependency.
- Dropped the `SwiftUITests` test target.

Both keep this a zero-dependency local package.
