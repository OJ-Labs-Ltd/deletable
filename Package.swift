// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Deletable",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Deletable",
            path: "Sources/Deletable"
        )
    ]
)
