// swift-tools-version: 6.3

import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
    .strictMemorySafety(),
]

let package = Package(
    name: "TabBarMenu",
    platforms: [
        .iOS("18.4")
    ],
    products: [
        .library(
            name: "TabBarMenu",
            targets: ["TabBarMenu"]
        ),
        .library(
            name: "TabBarMenuDemoSupport",
            targets: ["TabBarMenuDemoSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/lynnswap/ABIBridge", .upToNextMinor(from: "0.20.4")),
        .package(
            url: "https://github.com/swiftlang/swift-docc-plugin",
            from: "1.5.0"
        ),
    ],
    targets: [
        .target(
            name: "TabBarMenu",
            dependencies: [.product(name: "ABIBridge", package: "ABIBridge")],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "TabBarMenuDemoSupport",
            dependencies: ["TabBarMenu"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "TabBarMenuTests",
            dependencies: ["TabBarMenu"],
            swiftSettings: strictSwiftSettings
        ),
    ]
)
