# NeoPager — Product Requirements

## Overview

`neopager` is a modern terminal pager built in Swift using SwiftTUI. It replaces `more`/`less` for the everyday case: a command produces more output than fits on screen, you pipe it to a pager, and you want to move around that output naturally without memorizing pager arcana.

**Tech stack:** Swift 6, macOS 13+, SwiftTUI, swift-argument-parser, Swift Package Manager.

```
long-command | neopager      # page piped output
neopager file.txt            # page a file directly
```

---

## Problem

Unix pagers have been lacking for decades:

- `more` exits automatically when you reach the bottom of the output, which destroys the ability to scroll back up to re-read something — usually the entire reason you wanted a pager.
- Key bindings are invisible. Nothing on screen tells you how to move, search, or quit; you either know the keys or you're stuck (famously, "how do I exit vim/less").
- Movement is modal and uneven across pagers and platforms.

Applying a TUI approach — a persistent, visible status line and predictable, arrow-key-first navigation — makes the pager self-explanatory.

## Goals

1. Page output piped via stdin or read from a file argument.
2. A persistent bottom status line that always shows the movement keys and current position — the pager teaches itself.
3. Simple, predictable navigation: arrows for one line, Option-arrows for a full page, Esc to quit.
4. Never exit on reaching the bottom. The user stays in the pager until they press Esc.
5. (Phase 2) Search within the paged content.

## Non-goals (for now)

- Editing, multi-file navigation, or `less`-style command language.
- Following a growing file (`tail -f` / `less +F` mode).
- Streaming / incremental input. Phase 1 reads all content up front into a line buffer before the TUI starts (like `more`; `less` streams). Eager reading also lets stdin be fully drained before interactive input is rebound to `/dev/tty` (#0003). Incremental reading is a possible later enhancement, not a current goal.
- Linux/terminal-matrix portability. Phase 1 targets macOS terminals (Terminal.app, iTerm2, Ghostty).

---

## UX

### Layout

Two regions, full screen:

```
┌──────────────────────────────────────────────┐
│ line 1 of the piped output                   │
│ line 2                                       │
│ …                                            │  ← content viewport
│ line N (last visible)                        │
├──────────────────────────────────────────────┤
│ ↑/↓ line · ⌥↑/⌥↓ page · Esc quit    37% 120/4882 │  ← status bar (1 row)
└──────────────────────────────────────────────┘
```

### Key bindings — Phase 1

| Key | Action |
|---|---|
| `↑` / `↓` | Scroll one line up / down |
| `⌥↑` / `⌥↓` (Option-arrow) | Scroll one full page up / down |
| `Esc` | Exit the pager, restore the terminal |

Behavior rules:

- Scrolling clamps at the top and bottom. Reaching the bottom does **not** exit — the status bar shows `END` (or `100%`) and the user can scroll back up freely.
- On exit, the terminal is restored to its prior state (alternate screen buffer discarded, cursor restored), leaving the user's scrollback clean.
- The status bar always shows the key legend and the current position (percentage and `line/total`).

### Key bindings — Phase 2 (search)

| Key | Action |
|---|---|
| `/` | Open search input in the status bar |
| `Enter` | Run the search, jump to the first match at/after the current position |
| `n` / `N` | Next / previous match |
| `Esc` (while searching) | Cancel search input / clear highlights; a second Esc exits the pager |

Matches are highlighted in the viewport; the status bar shows the match count (`match 3/17`).

---

## Architecture

Follows the patterns proven in TerminalDashboard (`../TerminalDashboard`): ArgumentParser command → `MainActor.assumeIsolated { Application(rootView:).start() }`, `defaultIsolation(MainActor.self)` in Package.swift, SwiftTUI views composed like SwiftUI.

| Component | Responsibility |
|---|---|
| `NeoPagerCommand` | ArgumentParser entry; optional file argument; decides stdin-pipe vs file mode |
| `ContentSource` | Reads all content (pipe or file) into a line buffer before the TUI starts |
| `TTYInput` | Rebinds keyboard input to `/dev/tty` when stdin was consumed by the pipe |
| `KeyReader` | Decodes raw key events: arrows, Option-arrows, Esc |
| `PagerState` | Observable scroll model: offset, viewport height, clamping, search state |
| `PagerView` | SwiftTUI root view: viewport slice of lines + status bar |
| `StatusBar` | Key legend, position indicator, (Phase 2) search input and match count |

## Technical risks

These are the make-or-break items, front-loaded in the issue order:

1. **stdin vs keyboard** — in `cmd | neopager`, fd 0 is the pipe, not the keyboard. The pager must read all piped content, then reattach interactive input to `/dev/tty` (e.g. `dup2` onto fd 0) before SwiftTUI's `Application.start()` takes over input. Every real pager (`less`) does this; SwiftTUI was not written with it in mind. Spike first (#0003).
2. **Raw key handling in SwiftTUI** — SwiftTUI's input model is focus/Button oriented (TerminalDashboard uses only Tab/Enter/Buttons). The pager needs raw key events: plain arrows as scroll commands, Option-arrows, and bare Esc. This likely means extending or forking SwiftTUI's input layer (#0004).
3. **Escape-sequence ambiguity** — Option-↑/↓ arrive as escape sequences (`ESC[1;3A`/`ESC[1;3B`, or `ESC ESC [A` depending on terminal and "Option as Meta" settings), and a bare Esc press is a prefix of those sequences. Decoding needs a short timeout to distinguish "Esc alone" from "escape sequence in flight", and should accept the common variants across Terminal.app, iTerm2, and Ghostty.

## Phases

**Phase 1 — Core pager.** Pipe/file input, full-screen viewport, line + page scrolling, status bar, Esc to exit, resize handling. Exit criterion: `git log | neopager` is something you'd actually use daily.

**Phase 2 — Search.** `/` to enter a query, highlighted matches, `n`/`N` navigation, match count in the status bar.

## Issue map

| # | Title | Phase |
|---|---|---|
| [0001](issues/0001.md) | Add SwiftTUI dependency and configure package for macOS 13+ | 1 |
| [0002](issues/0002.md) | Read pager content from stdin pipe or file argument | 1 |
| [0003](issues/0003.md) | Reattach keyboard input to /dev/tty when stdin is a pipe | 1 |
| [0004](issues/0004.md) | Decode raw key events: arrows, Option-arrows, and Esc | 1 |
| [0005](issues/0005.md) | Render a viewport slice of the content sized to the terminal | 1 |
| [0006](issues/0006.md) | Scroll model: line and page movement with clamping, no auto-exit at bottom | 1 |
| [0007](issues/0007.md) | Bottom status bar with key legend and position indicator | 1 |
| [0008](issues/0008.md) | Esc exits the pager and restores the terminal cleanly | 1 |
| [0009](issues/0009.md) | Handle long lines and terminal resize | 1 |
| [0010](issues/0010.md) | Search input with match highlighting | 2 |
| [0011](issues/0011.md) | Next/previous match navigation and match count in status bar | 2 |
| [0012](issues/0012.md) | Preserve ANSI colors from piped input | 2 |
