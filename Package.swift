// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BenchmarkGame",
    products: [
        .executable(
            name: "Fasta",
            targets: ["Fasta"]),
        .library(
            name: "BenchmarkGame",
            targets: ["BenchmarkGame"]),
        .executable(
            name: "BinaryTrees",
            targets: ["BinaryTrees"]),
        .executable(
            name: "BinaryTrees-Fast",
            targets: ["BinaryTrees_Fast"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "BenchmarkGame",
            dependencies: []),
        .testTarget(
            name: "BenchmarkGameTests",
            dependencies: ["BenchmarkGame"]),
        .target(
            name: "Fasta",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "FastaTests",
            dependencies: ["Fasta"]),
        .target(
            name: "BinaryTrees",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
        .target(
            name: "BinaryTrees_Fast",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
    ]
)
