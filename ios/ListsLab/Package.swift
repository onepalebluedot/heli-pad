// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListsLab",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ListsKit", targets: ["ListsKit"]), .library(name: "ListsUI", targets: ["ListsUI"])],
    targets: [
        .target(name: "ListsKit"),
        .target(name: "ListsUI", dependencies: ["ListsKit"]),
        .testTarget(name: "ListsKitTests", dependencies: ["ListsKit", "ListsUI"])
    ]
)
