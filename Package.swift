// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClingySyncKit",
    platforms: [.macOS(.v14)], // SwiftData
    products: [
        .library(name: "ClingySyncKit", targets: ["ClingySyncKit"]),
    ],
    targets: [
        .target(
            name: "ClingySyncKit",
            swiftSettings: [.swiftLanguageMode(.v5)] // proving harness; tighten to v6 concurrency at Clingy integration
        ),
        .testTarget(
            name: "ClingySyncKitTests",
            dependencies: ["ClingySyncKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
