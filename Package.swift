// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlyBy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FlyBy",
            path: "Sources"
        )
    ]
)
