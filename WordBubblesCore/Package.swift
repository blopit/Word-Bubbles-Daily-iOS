// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WordBubblesCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WordBubblesCore", targets: ["WordBubblesCore"])],
    targets: [
        .target(name: "WordBubblesCore", resources: [.process("Resources")]),
        .testTarget(name: "WordBubblesCoreTests", dependencies: ["WordBubblesCore"], resources: [.copy("Fixtures")]),
    ]
)
