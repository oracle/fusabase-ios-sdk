// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fusabase-ios-sdk",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
        .tvOS(.v13),
        .watchOS(.v7)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FusabaseAuth",
            targets: ["FusabaseAuth"]
        ),
        .library(
            name: "FusabaseCore",
            targets: ["FusabaseCore"]
        ),
        .library(
            name: "FusabaseOracledb",
            targets: ["FusabaseOracledb"]
        ),
        .library(
            name: "FusabaseStorage",
            targets: ["FusabaseStorage"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FusabaseAuth",
            dependencies: ["FusabaseCore"]
        ),
        .target(
            name: "FusabaseCore"
        ),
        .target(
            name: "FusabaseOracledb",
            dependencies: ["FusabaseCore", "FusabaseAuth"]
        ),
        .target(
            name: "FusabaseStorage",
            dependencies: ["FusabaseCore", "FusabaseAuth"]
        ),
    ]
)
