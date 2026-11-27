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
        .target(
            name: "TreelabLanesUI",
            dependencies: ["TreelabLanes"],
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
            name: "TreelabLanesTests",
            dependencies: ["TreelabLanes"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
    ]
)
