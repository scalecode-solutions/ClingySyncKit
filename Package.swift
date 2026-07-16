// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClingySyncKit",
    platforms: [.macOS(.v14), .iOS(.v17)], // iOS: the consumer (Clingy); macOS: `swift test`. SwiftData floor.
    products: [
        .library(name: "ClingySyncKit", targets: ["ClingySyncKit"]),
    ],
    targets: [
        .target(
            name: "ClingySyncKit",
            // KNOWN DEBT: v5 mode under the 6.0 toolchain. In production use by
            // Clingy (Swift 6 strict) regardless — the consumer hand-carries the
            // isolation at the boundary. The v6 pass (@Sendable token provider,
            // async LocalStore contract, zero @unchecked) is scoped in STATUS.md
            // §3-4 and ships as a breaking 0.2.0.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClingySyncKitTests",
            dependencies: ["ClingySyncKit"],
            swiftSettings: [.swiftLanguageMode(.v5)] // flips to .v6 with the target (STATUS.md §3)
        ),
    ]
)
