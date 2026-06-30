// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AGANAL",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AGANAL", path: "Sources")
    ]
)
