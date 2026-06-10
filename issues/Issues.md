# NeoPager

A modern terminal pager (`neopager`) built in Swift with SwiftTUI. It pages output piped via stdin or read from a file, with a persistent bottom status line showing the movement keys (↑/↓ for one line, ⌥↑/⌥↓ for a page, Esc to quit) and never auto-exits at the bottom like `more` does. See `PRD.md` at the repo root for the full product spec and phase plan.

This file is the local guide for managing issues in this project. The companion Mac app (Issues.app) watches the `issues/` folder and renders the current state. Markdown files (and `project.json`) are the source of truth — there is no generated artifact or index to keep in sync.

## Folder layout

```
issues/
├── project.json       # canonical project name + repo URL
├── Issues.md          # this file
├── 0001.md            # one file per issue
└── …
```

## Status values

| File value | Display name | Meaning |
|---|---|---|
| `open` | Open | Filed but not yet started |
| `in-progress` | In Progress | Actively being worked on |
| `resolved` | Resolved | Work is done; awaiting user confirmation |
| `closed` | Closed | User has confirmed the fix |
| `wontfix` | Won't Fix | Acknowledged but won't be addressed |

## Critical rule: never close without explicit confirmation

An issue must **never** be marked `resolved`, `closed`, or `wontfix` based on inference. Only when the user has said so in plain language. A subagent that finishes a fix may set `resolved` (work-is-done-but-not-confirmed); only the user moves an issue to `closed`.

## Git tracking

This project is not currently a git repository, so issue lifecycle events are working-copy edits only — no commits. If the project is later initialized as a git repo with `issues/` tracked, follow the standard two-commit resolve flow (code commit `#NNNN <verb> <title>`, then resolution commit `#NNNN Resolve: <title>`).

## Build / verify command

```bash
./build.sh clean build
```

To verify interactively, pipe real output through the pager, e.g. `git -C ../TerminalDashboard log | swift run neopager`.

## Issue file format

Each issue is `NNNN.md` (4-digit zero-padded). Title separator is an em-dash (`—`). Metadata table rows keep the field name in `**bold**`. `## Description` must be the first `##` section after the metadata table; resolution sections (`## Root cause`, `## Fix`, `## Verification`, `## Files changed`, optional `## Gotchas`) go after it when an issue is resolved. When status moves to `resolved`/`closed`, add a `**Closed**` row, plus a `**Commit**` row when there is a fix commit.

For feature-gap issues (most of this project's initial queue), Description + Expected behavior + Notes is enough — Steps/Actual are for genuine bugs.

## Module conventions

- `Package` — Package.swift, build configuration, build.sh
- `CLI` — ArgumentParser entry point, arguments and flags
- `Input` — content reading (stdin pipe / file), /dev/tty rebinding
- `Keys` — raw key event decoding (arrows, Option-arrows, Esc)
- `Pager` — scroll model / state (offsets, clamping, search state)
- `Views` — SwiftTUI views (viewport, status bar)
- `Search` — phase 2 search features
