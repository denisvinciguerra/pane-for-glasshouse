// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PaneKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PaneKit", targets: ["PaneKit"])],
    targets: [
        .target(name: "PaneKit", resources: [.process("Resources")]),
        .testTarget(name: "PaneKitTests", dependencies: ["PaneKit"], resources: [.copy("Fixtures")]),
    ]
)
