// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package (
    name: "MediaKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ], products: [
        .library(name: "MediaKit", targets: ["MediaKit"]),
    ], dependencies: [
        .package(url: "https://www.github.com/Vaida12345/FinderItem", from: "1.0.0"),
        .package(url: "https://www.github.com/Vaida12345/ConcurrentStream", from: "0.1.0"),
        .package(url: "https://www.github.com/Vaida12345/DetailedDescription", from: "1.0.0"),
        .package(url: "https://www.github.com/Vaida12345/NativeImage", from: "1.0.0"),
        .package(url: "https://www.github.com/Vaida12345/Optimization", from: "1.0.0"),
    ], targets: [
        .target(name: "MediaKit", dependencies: ["FinderItem", "ConcurrentStream", "DetailedDescription", "NativeImage", "Optimization"], path: "MediaKit"),
        .executableTarget(name: "Client", dependencies: ["MediaKit"], path: "Client"),
        .testTarget(name: "Tests", dependencies: ["MediaKit", "FinderItem", "ConcurrentStream", "DetailedDescription", "NativeImage"], path: "Tests")
    ], swiftLanguageModes: [.v5]
)
