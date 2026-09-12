// swift-tools-version: 6.0
import PackageDescription

// Standalone work stream for PREWALK_PLAN.md section C (the app-only assistant).
// Deliberately has no dependency on the HeliPad app target: the app is reached
// only through the ports in `AssistantKit/Boundary`, and `AssistantMocks`
// supplies a fixture implementation so the chat can be exercised end to end
// before any integration happens.
let package = Package(
    name: "AssistantLab",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AssistantKit", targets: ["AssistantKit"]),
        .library(name: "AssistantMocks", targets: ["AssistantMocks"]),
        .library(name: "AssistantUI", targets: ["AssistantUI"]),
        .library(name: "AssistantDevRelay", targets: ["AssistantDevRelay"]),
        .executable(name: "AssistantHarness", targets: ["AssistantHarness"])
    ],
    targets: [
        .target(name: "AssistantKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "AssistantMocks", dependencies: ["AssistantKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "AssistantUI", dependencies: ["AssistantKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Development only: reads a real OpenAI key from .env and calls the
        // provider directly. Linked by the command-line harness and by nothing
        // else. AssistantKit and AssistantUI must never depend on it - that
        // separation is what keeps a provider key out of anything shippable.
        .target(name: "AssistantDevRelay", dependencies: ["AssistantKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "AssistantHarness",
            dependencies: ["AssistantKit", "AssistantMocks", "AssistantDevRelay"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AssistantKitTests",
            dependencies: ["AssistantKit", "AssistantMocks", "AssistantDevRelay"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
