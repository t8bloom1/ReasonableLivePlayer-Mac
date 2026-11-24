// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReasonableLivePlayer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReasonableLivePlayer", targets: ["ReasonableLivePlayer"])
    ],
    targets: [
        // Models, persistence, MIDI, Reason automation and the playlist state machine.
        // No SwiftUI, so it can be unit tested without a UI.
        .target(
            name: "RLPCore",
            path: "Sources/RLPCore"
        ),
        // SwiftUI application.
        .executableTarget(
            name: "ReasonableLivePlayer",
            dependencies: ["RLPCore"],
            path: "Sources/ReasonableLivePlayer"
        ),
        .testTarget(
            name: "RLPCoreTests",
            dependencies: ["RLPCore"],
            path: "Tests/RLPCoreTests"
        ),
    ]
)
