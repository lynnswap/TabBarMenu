// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
        // Products define the executables and libraries a package produces, making them visible to other packages.
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
        .package(url: "https://github.com/lynnswap/ABIBridge", from: "0.8.0"),
        .package(
            url: "https://github.com/swiftlang/swift-docc-plugin",
            from: "1.5.0"
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
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
