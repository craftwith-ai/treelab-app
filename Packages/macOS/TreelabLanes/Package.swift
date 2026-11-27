// swift-tools-version: 6.0

import PackageDescription

// Treelab's own package: the app reads the state lab writes for it and acts through lab's
// commands (the "brain" stays in lab, a separate private program). Leaf package, no cmux
// dependency, so upstream merges never touch it.
let package = Package(
    name: "TreelabLanes",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "TreelabLanes", targets: ["TreelabLanes"]),
        .library(name: "TreelabLanesUI", targets: ["TreelabLanesUI"]),
        .library(name: "TreelabGinkgo", targets: ["TreelabGinkgo"]),
    ],
    targets: [
        .target(
            name: "TreelabLanes",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        // Ginkgo.app's direct channel (contract v1): a local socket of the same user, no network,
        // no sound. Kept apart so the lanes brain keeps 0 socket.
        .target(
            name: "TreelabGinkgo",
            dependencies: ["TreelabLanes"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .target(
            name: "TreelabLanesUI",
            dependencies: ["TreelabLanes", "TreelabGinkgo"],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "TreelabGinkgoTests",
            dependencies: ["TreelabGinkgo", "TreelabLanes"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "TreelabLanesUITests",
            dependencies: ["TreelabLanesUI", "TreelabGinkgo"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "TreelabLanesTests",
            dependencies: ["TreelabLanes"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
    ]
)
