// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Reponomi",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ReponomiCore"),
        .executableTarget(name: "Reponomi", dependencies: ["ReponomiCore"]),
        .testTarget(name: "ReponomiCoreTests", dependencies: ["ReponomiCore"]),
    ]
)
