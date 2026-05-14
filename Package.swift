// swift-tools-version: 6.1
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
        .package(url: "https://github.com/Vaida12345/FinderItem.git", from: "2.0.0"),
        .package(url: "https://github.com/Vaida12345/ConcurrentStream.git", from: "1.0.0"),
        .package(url: "https://github.com/Vaida12345/DetailedDescription.git", from: "2.0.3"),
        .package(url: "https://github.com/Vaida12345/NativeImage.git", from: "1.3.0"),
        .package(url: "https://github.com/Vaida12345/Optimization.git", from: "1.0.0"),
        .package(url: "https://github.com/Vaida12345/Swift-FLAC.git", from: "1.0.0"),
    ], targets: [
        .target(name: "MediaKit", dependencies: ["FinderItem", "ConcurrentStream", "DetailedDescription", "NativeImage", "Optimization", .product(name: "SwiftFLAC", package: "swift-flac")], path: "MediaKit"),
        .executableTarget(name: "Client", dependencies: ["MediaKit"], path: "Client"),
        .testTarget(name: "Tests", dependencies: ["MediaKit", "FinderItem", "ConcurrentStream", "DetailedDescription", "NativeImage"], path: "Tests")
    ], swiftLanguageModes: [.v5]
)
