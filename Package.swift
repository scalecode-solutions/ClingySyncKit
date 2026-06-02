// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClingySyncKit",
    platforms: [.macOS(.v14), .iOS(.v17)], // SwiftData (iOS 17+); iOS added for Clingy integration
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
