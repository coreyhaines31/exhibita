// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExhibitCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ExhibitCore", targets: ["ExhibitCore"]),
        .library(name: "ExhibitTargets", targets: ["ExhibitTargets"]),
        .library(name: "ExhibitCLI", targets: ["ExhibitCLI"]),
        .library(name: "ExhibitInterpret", targets: ["ExhibitInterpret"]),
        .library(name: "ExhibitStore", targets: ["ExhibitStore"]),
        .library(name: "ExhibitShell", targets: ["ExhibitShell"]),
        .library(name: "ExhibitEditor", targets: ["ExhibitEditor"]),
        .library(name: "ExhibitBridge", targets: ["ExhibitBridge"]),
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
            "ExhibitCore", "ExhibitTargets", "ExhibitInterpret", "ExhibitBridge", "ExhibitShell", "ExhibitStore",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]),
        .executableTarget(name: "exhibit", dependencies: ["ExhibitCLI"]),
        // Instructions to operations: the interpreter contract, the grammar and the loopback model client. Text in,
        // never the image.
        .target(name: "ExhibitInterpret", dependencies: ["ExhibitCore"]),
        // The interpreter and speech spike (issue 3): `swift run exhibit-eval`. Not shipped. Uses FoundationModels
        // and SpeechAnalyzer behind macOS 26 availability checks.
        .executableTarget(name: "exhibit-eval", dependencies: ["ExhibitInterpret", "ExhibitCore"], path: "Sources/ExhibitEval"),
        // History for the app: captures under Application Support, retention and purge. No AppKit.
        .target(name: "ExhibitStore", dependencies: ["ExhibitCore"]),
        // The app shell's decisions as plain logic: hotkeys and their conflicts, selection geometry, window
        // picking, history rows, permission state, the capture policy hook. No AppKit, so all of it is tested here.
        .target(name: "ExhibitShell", dependencies: ["ExhibitCore", "ExhibitStore"]),
        // The editor's brain: tools, keys, gestures, snapping, selection, undo, and the one owner of an open
        // capture's document. No AppKit, so all of it is tested here; the app draws it and forwards events.
        .target(name: "ExhibitEditor", dependencies: ["ExhibitCore", "ExhibitStore", "ExhibitShell"]),
        // The capture bridge: the CLI asks the running app for live captures over a Unix socket. The protocol, the
        // socket server and client, and the agent capture pipeline behind a capture provider. No AppKit.
        .target(name: "ExhibitBridge", dependencies: ["ExhibitCore", "ExhibitStore", "ExhibitShell", "ExhibitTargets"]),
        // Synthetic screenshots shared by the test targets. Not a product.
        .target(name: "ExhibitFixtures", dependencies: ["ExhibitCore"]),
        // Goldens are read and written through #filePath, so they are not bundled as resources.
        .testTarget(name: "ExhibitCoreTests", dependencies: ["ExhibitCore", "ExhibitFixtures"], exclude: ["Goldens"]),
        .testTarget(name: "ExhibitStoreTests", dependencies: ["ExhibitStore", "ExhibitCore", "ExhibitFixtures"]),
        .testTarget(name: "ExhibitShellTests", dependencies: ["ExhibitShell", "ExhibitStore", "ExhibitCore"]),
        .testTarget(name: "ExhibitEditorTests",
                    dependencies: ["ExhibitEditor", "ExhibitCore", "ExhibitStore", "ExhibitShell", "ExhibitFixtures"]),
        .testTarget(name: "ExhibitBridgeTests",
                    dependencies: ["ExhibitBridge", "ExhibitShell", "ExhibitStore", "ExhibitCore", "ExhibitFixtures"]),
        .testTarget(name: "ExhibitInterpretTests", dependencies: ["ExhibitInterpret", "ExhibitCore"]),
        .testTarget(name: "ExhibitTargetsTests", dependencies: ["ExhibitTargets", "ExhibitCore", "ExhibitFixtures"]),
        // Depends on the executable so `swift test` builds the real binary for the end-to-end tests.
        .testTarget(name: "ExhibitCLITests",
                    dependencies: ["ExhibitCLI", "exhibit", "ExhibitCore", "ExhibitTargets", "ExhibitFixtures",
                                   "ExhibitInterpret", "ExhibitBridge"])
    ]
)
