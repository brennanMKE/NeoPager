#!/bin/zsh
set -euo pipefail

cd "${0:a:h}"

# Where `install` copies the binary. Override with: INSTALL_DIR=/path ./build.sh install
INSTALL_DIR="${INSTALL_DIR:-$HOME/bin}"

usage() {
    echo "Usage: ./build.sh <action> [<action> ...]"
    echo ""
    echo "Actions:"
    echo "  clean      Remove build artifacts"
    echo "  resolve    Resolve package dependencies"
    echo "  update     Update package dependencies to latest versions"
    echo "  build      Build (debug)"
    echo "  release    Build (release, native arch)"
    echo "  universal  Build (release, universal arm64 + x86_64)"
    echo "  install    Copy the release binary to \$INSTALL_DIR (default: ~/bin)"
    echo "  run        Run the executable (debug)"
    echo ""
    echo "Actions run in sequence and stop on the first failure."
    echo "Typical install:  ./build.sh release install"
}

clean() {
    swift package clean
    rm -rf .build
}

resolve() {
    swift package resolve
}

update() {
    swift package update
}

build() {
    swift build
}

release() {
    swift build -c release
}

universal() {
    swift build -c release --arch arm64 --arch x86_64
}

install() {
    # Prefer the native release; fall back to a universal build if that's all
    # there is. (For a universal install, run: ./build.sh clean universal install)
    local bin
    if [[ -f .build/release/neopager ]]; then
        bin=.build/release/neopager
    elif [[ -f .build/apple/Products/Release/neopager ]]; then
        bin=.build/apple/Products/Release/neopager
    else
        echo "No release binary found. Run './build.sh release' (or 'universal') first." >&2
        return 1
    fi

    mkdir -p "$INSTALL_DIR" || { echo "Cannot create $INSTALL_DIR" >&2; return 1; }
    if ! cp "$bin" "$INSTALL_DIR/neopager"; then
        echo "Could not write to $INSTALL_DIR." >&2
        echo "Try a writable dir, e.g.: INSTALL_DIR=/usr/local/bin sudo ./build.sh install" >&2
        return 1
    fi
    chmod +x "$INSTALL_DIR/neopager"
    echo "Installed neopager ($(lipo -archs "$INSTALL_DIR/neopager" 2>/dev/null || echo unknown)) -> $INSTALL_DIR/neopager"

    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *) echo "Note: $INSTALL_DIR is not on your PATH. Add it, e.g.:"
           echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
    esac
}

run() {
    swift run neopager
}

if (( $# == 0 )); then
    usage
    exit 1
fi

for action in "$@"; do
    case "$action" in
        clean|resolve|update|build|release|universal|install|run)
            echo "==> $action"
            "$action"
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown action: $action" >&2
            usage
            exit 1
            ;;
    esac
done
