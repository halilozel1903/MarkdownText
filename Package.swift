// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownText",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MarkdownText", targets: ["MarkdownText"]),
    ],
    targets: [
        .target(name: "MarkdownText"),
        .testTarget(name: "MarkdownTextTests", dependencies: ["MarkdownText"]),
    ]
)
