// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AGANAL",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AGANAL", path: "Sources")
    ]
)
