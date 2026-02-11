// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRStatusWatcher",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
    ],
    targets: [
        .executableTarget(
            name: "PRStatusWatcher",
            path: "Sources",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "PRStatusWatcherTests",
            dependencies: ["PRStatusWatcher"],
            path: "Tests"
        )
    ]
)
