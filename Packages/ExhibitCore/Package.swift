// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExhibitCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ExhibitCore", targets: ["ExhibitCore"]),
        .library(name: "ExhibitTargets", targets: ["ExhibitTargets"]),
        .library(name: "ExhibitCLI", targets: ["ExhibitCLI"]),
        .executable(name: "exhibit", targets: ["exhibit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.7.1")
    ],
    targets: [
        .target(name: "ExhibitCore"),
        // Vision lives here, so ExhibitCore stays free of it.
        .target(name: "ExhibitTargets", dependencies: ["ExhibitCore"]),
        // Every command's logic, so tests can drive it in process. The executable is a thin shell over it.
        .target(name: "ExhibitCLI", dependencies: [
            "ExhibitCore", "ExhibitTargets", .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .executableTarget(name: "exhibit", dependencies: ["ExhibitCLI"]),
        // Synthetic screenshots shared by the test targets. Not a product.
        .target(name: "ExhibitFixtures", dependencies: ["ExhibitCore"]),
        // Goldens are read and written through #filePath, so they are not bundled as resources.
        .testTarget(name: "ExhibitCoreTests", dependencies: ["ExhibitCore", "ExhibitFixtures"], exclude: ["Goldens"]),
        .testTarget(name: "ExhibitTargetsTests", dependencies: ["ExhibitTargets", "ExhibitCore", "ExhibitFixtures"]),
        // Depends on the executable so `swift test` builds the real binary for the end-to-end tests.
        .testTarget(name: "ExhibitCLITests",
                    dependencies: ["ExhibitCLI", "exhibit", "ExhibitCore", "ExhibitTargets", "ExhibitFixtures"])
    ]
)
