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
        .testTarget(name: "ExhibitCoreTests", dependencies: ["ExhibitCore"])
    ]
)
