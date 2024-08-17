// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package (
    name: "MediaKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17)
    ], products: [
        .library(name: "MediaKit", targets: ["MediaKit"]),
    ], dependencies: [
        .package(name: "Stratum",
                 path: "/Users/vaida/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Projects/Packages/Stratum"),
        .package(name: "ConcurrentStream",
                 path: "~/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Projects/Packages/ConcurrentStream"),
        .package(name: "DetailedDescription",
                 path: "~/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Projects/Packages/DetailedDescription")
    ], targets: [
        .target(name: "MediaKit", dependencies: ["Stratum", "ConcurrentStream", "DetailedDescription"]),
        .testTarget(name: "Tests", dependencies: ["MediaKit"]),
        .executableTarget(name: "Client", dependencies: ["MediaKit"])
    ], swiftLanguageModes: [.v5]
)
