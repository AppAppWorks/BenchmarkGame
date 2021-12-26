// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BenchmarkGame",
    products: [
        .executable(
            name: "Fasta-Fast",
            targets: ["Fasta_Fast"]),
        .executable(
            name: "Fasta-Swift3",
            targets: ["Fasta_Swift3"]),
        .library(
            name: "BenchmarkGame",
            targets: ["BenchmarkGame"]),
        .executable(
            name: "BinaryTrees_Swift3",
            targets: ["BinaryTrees_Swift3"]),
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
            name: "Fasta_Fast",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
        .target(
            name: "Fasta_Swift3",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "Fasta_FastTests",
            dependencies: ["Fasta_Fast"]),
        .testTarget(
            name: "Fasta_Swift3Tests",
            dependencies: ["Fasta_Swift3"]),
        .target(
            name: "BinaryTrees_Swift3",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "BinaryTrees_Swift3Tests",
            dependencies: [
                "BinaryTrees_Swift3",
            ]
        ),
        .target(
            name: "BinaryTrees_Fast",
            swiftSettings: [
                .unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "BinaryTrees_FastTests",
            dependencies: [
                "BinaryTrees_Fast",
            ]
        ),
    ]
)
