// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [.library(name: "DockCatCore", targets: ["DockCatCore"])]
var targets: [Target] = [
    .target(name: "DockCatCore"),
    .testTarget(name: "DockCatCoreTests", dependencies: ["DockCatCore"])
]

#if os(macOS)
products.append(.executable(name: "DockCat", targets: ["DockCat"]))
targets.append(.executableTarget(name: "DockCat", dependencies: ["DockCatCore"], resources: [.process("Resources")]))
targets.append(.testTarget(name: "DockCatTests", dependencies: ["DockCat"]))
#endif

let package = Package(name: "DockCat", platforms: [.macOS(.v14)], products: products, targets: targets)
