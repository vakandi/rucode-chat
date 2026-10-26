// swift-tools-version:5.9
import PackageDescription

// Command-Line-Tools build of RuCode Chat (no Xcode installed on this machine).
// The Xcode project remains the upstream source of truth for targets and signing;
// this manifest only mirrors its macOS sources and pinned dependencies.
let package = Package(
    name: "RuCodeChat",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
        .package(url: "https://github.com/exyte/ActivityIndicatorView.git", exact: "1.1.1"),
        .package(url: "https://github.com/AugustDev/Splash", revision: "c31eba0866102be9be29391dac641ecb46795702"),
        .package(url: "https://github.com/AugustDev/Magnet", revision: "4865f86d9baa24684dedacd6677beb2d8b30d88e"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.0.1"),
        .package(url: "https://github.com/ksemianov/WrappingHStack", exact: "0.2.0"),
        .package(url: "https://github.com/twostraws/Vortex", exact: "1.0.1"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "RuCodeChat",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "ActivityIndicatorView", package: "ActivityIndicatorView"),
                .product(name: "Splash", package: "Splash"),
                .product(name: "Magnet", package: "Magnet"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "WrappingHStack", package: "WrappingHStack"),
                .product(name: "Vortex", package: "Vortex"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "build/generated-sources/RuCodeChat"
        )
    ],
    swiftLanguageVersions: [.v5]
)
