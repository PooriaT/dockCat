// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockCat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DockCatCore", targets: ["DockCatCore"]),
        .executable(name: "DockCat", targets: ["DockCat"])
    ],
    targets: [
        .target(name: "DockCatCore"),
        .executableTarget(
            name: "DockCat",
            dependencies: ["DockCatCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DockCatCoreTests", dependencies: ["DockCatCore"])
    ]
)
