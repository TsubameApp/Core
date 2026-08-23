// swift-tools-version: 6.3
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
        .systemLibrary(name: "CSQLiteSystem"),
        .target(
            name: "CSQLiteBundled",
            path: "Sources/CSQLiteBundled",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_DQS", to: "0"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
                .define("SQLITE_THREADSAFE", to: "1")
            ]
        ),
        .target(
            name: "TsubameCore",
            dependencies: [
                .target(
                    name: "CSQLiteSystem",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .target(
                    name: "CSQLiteBundled",
                    condition: .when(platforms: [.windows])
                )
            ]
        ),
        .executableTarget(name: "TsubameCLI", dependencies: ["TsubameCore"]),
        .testTarget(name: "TsubameCoreTests", dependencies: ["TsubameCore"])
    ]
)
