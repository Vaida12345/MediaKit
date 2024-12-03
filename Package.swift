// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package (
    name: "MediaKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ], products: [
        .library(name: "MediaKit", targets: ["MediaKit"]),
    ], dependencies: [
        .package(url: "https://github.com/Vaida12345/FinderItem.git", from: "1.0.0"),
        .package(url: "https://github.com/Vaida12345/ConcurrentStream.git", from: "0.1.0"),
        .package(url: "https://github.com/Vaida12345/DetailedDescription.git", from: "1.0.0"),
        .package(url: "https://github.com/Vaida12345/NativeImage.git", from: "1.0.0"),
    ], targets: [
        .target(name: "MediaKit", dependencies: ["FinderItem", "ConcurrentStream", "DetailedDescription", "NativeImage"], path: "MediaKit"),
        .executableTarget(name: "Client", dependencies: ["MediaKit"], path: "Client")
    ], swiftLanguageModes: [.v5]
)
