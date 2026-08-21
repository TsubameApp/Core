// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TsubameCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TsubameCore", targets: ["TsubameCore"]),
        .executable(name: "TsubameCLI", targets: ["TsubameCLI"])
    ],
    targets: [
        .target(name: "TsubameCore"),
        .executableTarget(name: "TsubameCLI", dependencies: ["TsubameCore"])
    ]
)
