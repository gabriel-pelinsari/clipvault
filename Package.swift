// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "ClipVault",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipVault",
            path: "Sources/ClipVault",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ClipVaultTests",
            dependencies: ["ClipVault"],
            path: "Tests/ClipVaultTests",
            swiftSettings: swiftSettings
        ),
    ]
)
