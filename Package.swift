// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GitStatusBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GitStatusBar",
            path: "Sources/GitStatusBar"
        )
    ]
)
