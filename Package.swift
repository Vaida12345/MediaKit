// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package (
    name: "MediaKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16)
    ], products: [
        .library(name: "MediaKit", targets: ["MediaKit"]),
    ], dependencies: [
        .package(name: "Stratum", path: "/Users/vaida/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Projects/Packages/Stratum")
    ], targets: [
        .target(name: "MediaKit", dependencies: ["Stratum"]),
        .testTarget(name: "Tests", dependencies: ["MediaKit"]),
    ]
)
