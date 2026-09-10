// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dictation",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Dictation",
            path: "Sources",
            swiftSettings: [
                // Same footing as Minimal: keep v5 semantics until the
                // AppKit/Speech callbacks are audited for strict concurrency.
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
