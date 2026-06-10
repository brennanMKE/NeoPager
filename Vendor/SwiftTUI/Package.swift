// swift-tools-version: 5.6

import PackageDescription

// Vendored copy of SwiftTUI (https://github.com/rensbreur/SwiftTUI), MIT-licensed,
// carried locally so NeoPager can patch the input layer (raw arrow/Option-arrow/Esc
// key events and a key-event hook) — upstream has no such hook and hardcodes arrow
// keys to focus movement. See VENDORING.md for the pinned revision and patch notes.
//
// Trimmed from upstream: the swift-docc-plugin dependency and the test target are
// dropped so this stays a zero-dependency local package.
let package = Package(
    name: "SwiftTUI",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "SwiftTUI",
            targets: ["SwiftTUI"]),
    ],
    targets: [
        .target(
            name: "SwiftTUI",
            dependencies: []),
    ]
)
