# NeoPager

A modern terminal pager (`neopager`) for macOS, built in Swift with
[SwiftTUI](https://github.com/rensbreur/SwiftTUI). It replaces `more`/`less` for
the everyday case: a command produces more output than fits on screen, you pipe it
to a pager, and you move around naturally — without memorizing pager arcana.

The two things that set it apart from `more`/`less`:

- **A persistent status bar** that always shows the movement keys and your position,
  so the pager teaches itself — no more "how do I quit this?"
- **It never auto-exits at the bottom** (the original sin of `more`). You stay in
  the pager until you press `Esc` or `q`.

```
↑/↓ line · ⌥↑/⌥↓ page · Esc quit                    37%  120/4882
```

## Features

- Pipe input (`cmd | neopager`) or a file argument (`neopager file.txt`)
- Arrow-key-first navigation, plus the `less`/`more` muscle-memory keys (`Space`, `b`, `g`, `G`, `q`)
- Wraps long lines by default; chop + horizontal scroll with `-S`
- Incremental search with match highlighting (`/`, `n`, `N`)
- Preserves **ANSI color** from piped input (`git log --color`, `ls -G`, …)
- Prints and exits without paging when the content already fits on one screen
  (like `less -F`)
- Restores the terminal cleanly on exit (no scrollback pollution)
- Adapts to terminal resizes

## Requirements

- **macOS 13 or later** (to run a built binary)
- A **Swift 6 toolchain** (Xcode or the Swift toolchain) to build it

## Install

```bash
git clone <this-repo> && cd NeoPager
./build.sh release install
```

`install` builds an optimized binary and copies it to `~/bin/neopager`. Override the
destination with `INSTALL_DIR`:

```bash
INSTALL_DIR=/usr/local/bin ./build.sh install   # may need sudo
```

If the install directory isn't on your `PATH`, `build.sh` will tell you how to add it.

The binary is self-contained — its dependencies are statically linked, so it only
needs the system Swift runtime that ships with macOS 13+. To put it on another Mac,
just copy it: `scp ~/bin/neopager othermac:~/bin/`. (If macOS quarantines it after an
AirDrop/download, clear that with `xattr -dr com.apple.quarantine ~/bin/neopager`.)

## Usage

```bash
some-command | neopager      # page piped output
neopager file.txt            # page a file
git log | neopager           # the daily driver
neopager -S wide-output.txt  # chop long lines instead of wrapping
```

| Option | Description |
|---|---|
| `<file>` | File to page. If omitted, reads from a stdin pipe. |
| `-S`, `--chop-long-lines` | Chop long lines at the right edge instead of wrapping. |
| `-h`, `--help` | Show help. |

If you run `neopager` with no file and nothing piped in, it prints usage and exits
rather than waiting on an empty terminal.

## Key bindings

| Key | Action |
|---|---|
| `↑` / `↓` | Scroll one line |
| `⌥↑` / `⌥↓`, `PgUp` / `PgDn` | Scroll one page |
| `Space` / `b` | Page down / up |
| `d` / `u` | Half page down / up |
| `g` / `G`, `Home` / `End` | Jump to top / bottom |
| `←` / `→` | Scroll sideways (only in chop mode, `-S`) |
| `/` | Search |
| `n` / `N` | Next / previous match |
| `h` / `F1` | Toggle the help overlay |
| `Esc` / `q`, `Ctrl-C` | Quit |

Reaching the bottom shows `END` in the status bar and does **not** exit — scroll
back up freely.

### Search

Press `/`, type a query (case-insensitive), and press `Enter`. The view jumps to the
first match at or after your position and highlights all visible matches; the status
bar shows `match 3/17`. Use `n` / `N` to walk the matches. A first `Esc` clears the
highlights; a second `Esc` quits.

## Use it as your default pager (zsh)

Add this to `~/.zshrc` so `$PAGER` is only set when `neopager` is actually installed:

```zsh
# Use neopager as the pager, but only if it's installed
if [[ -x "$HOME/bin/neopager" ]]; then
  export PAGER="$HOME/bin/neopager"
fi
```

Then reload: `source ~/.zshrc` (or open a new terminal).

### Git

Git uses its own pager setting first, so point it at `neopager` directly to get
colorized diffs and logs:

```bash
git config --global core.pager neopager
```

Short diffs/logs that fit on one screen will just print (no full-screen takeover),
matching the common `LESS=-FRX` experience.

### man pages

macOS `man` renders bold/underline with *overstrike* rather than ANSI color, which
`neopager` doesn't decode — so man pages will page fine but look plainer. If you'd
rather keep `man` on `less`, leave `MANPAGER` pointed at it:

```zsh
export MANPAGER=less
```

> Note: `neopager` ignores the `LESS` environment variable (that's a `less`-only
> setting) — harmless if you have one set.

## Building from source

`build.sh` wraps the common Swift Package Manager tasks:

| Action | What it does |
|---|---|
| `./build.sh build` | Debug build |
| `./build.sh release` | Optimized release build (native arch) |
| `./build.sh universal` | Release build, universal (arm64 + x86_64) |
| `./build.sh install` | Copy the release binary to `$INSTALL_DIR` (default `~/bin`) |
| `./build.sh run` | Run the debug build |
| `./build.sh clean` | Remove build artifacts |

Actions can be chained, e.g. `./build.sh clean release install`.

Run the tests with:

```bash
swift test
```

## Project layout

- `Sources/NeoPager/` — the pager (CLI, content loading, scroll model, views)
- `Vendor/SwiftTUI/` — a vendored, lightly patched copy of SwiftTUI (raw key-event
  support the upstream library lacks; see `Vendor/SwiftTUI/VENDORING.md`)
- `Tests/NeoPagerTests/` — unit tests (Swift Testing)
- `issues/` — the project's issue history
- `PRD.md` — the product requirements and design notes

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Brennan Stehling.

The vendored SwiftTUI is also MIT-licensed (© 2022 Rens Breur); see
`Vendor/SwiftTUI/LICENSE`.
