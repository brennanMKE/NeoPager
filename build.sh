#!/bin/zsh
set -euo pipefail

cd "${0:a:h}"

usage() {
    echo "Usage: ./build.sh <action> [<action> ...]"
    echo ""
    echo "Actions:"
    echo "  clean      Remove build artifacts"
    echo "  resolve    Resolve package dependencies"
    echo "  update     Update package dependencies to latest versions"
    echo "  build      Build (debug)"
    echo "  release    Build (release)"
    echo "  run        Run the executable (debug)"
    echo ""
    echo "Actions run in sequence and stop on the first failure."
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

run() {
    swift run NeoPager
}

if (( $# == 0 )); then
    usage
    exit 1
fi

for action in "$@"; do
    case "$action" in
        clean|resolve|update|build|release|run)
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
