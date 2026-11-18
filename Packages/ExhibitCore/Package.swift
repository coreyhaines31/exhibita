// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExhibitCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ExhibitCore", targets: ["ExhibitCore"])
    ],
    targets: [
        .target(name: "ExhibitCore"),
        // Goldens are read and written through #filePath, so they are not bundled as resources.
        .testTarget(name: "ExhibitCoreTests", dependencies: ["ExhibitCore"], exclude: ["Goldens"])
    ]
)
