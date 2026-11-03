// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PaneKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PaneKit", targets: ["PaneKit"])],
    targets: [
        .target(name: "PaneKit", resources: [.process("Resources/Localizable.xcstrings"), .copy("Resources/Demo")]),
        .testTarget(name: "PaneKitTests", dependencies: ["PaneKit"], resources: [.copy("Fixtures")]),
    ]
)
