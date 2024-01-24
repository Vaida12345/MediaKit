// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PDFUtilities",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PDFUtilities",
            targets: ["PDFUtilities"]),
    ],
    dependencies: [.package(name: "Nucleus", path: "/Users/vaida/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Projects/Packages/DataBase")],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PDFUtilities", dependencies: ["Nucleus"]),
        .testTarget(
            name: "PDFUtilitiesTests",
            dependencies: ["PDFUtilities"]),
    ]
)
