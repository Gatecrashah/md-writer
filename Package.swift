// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDWriter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MDWriter", path: "Sources/MDWriter")
    ]
)
