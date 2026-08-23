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
        .systemLibrary(
            name: "CSQLiteSystem",
            path: "Sources/ThirdParty/CSQLiteSystem"
        ),
        .target(
            name: "CSQLiteBundled",
            path: "Sources/ThirdParty/CSQLiteBundled",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_DQS", to: "0"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
                .define("SQLITE_THREADSAFE", to: "1")
            ]
        ),
        .target(
            name: "CMiniz",
            path: "Sources/ThirdParty/CMiniz",
            publicHeadersPath: "include",
            cSettings: [
                .define("MINIZ_NO_DEFLATE_APIS"),
                .define("MINIZ_NO_ZLIB_APIS"),
                .define("MINIZ_NO_ZLIB_COMPATIBLE_NAMES")
            ]
        ),
        .target(
            name: "CTsubameZIP",
            dependencies: ["CMiniz"],
            path: "Sources/Interop/CTsubameZIP",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TsubameCore",
            dependencies: [
                "CTsubameZIP",
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
