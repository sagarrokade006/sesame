// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SesameCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SesameCore", targets: ["SesameCore"])],
    targets: [
        .target(name: "SesameCore"),
        .testTarget(name: "SesameCoreTests", dependencies: ["SesameCore"]),
    ]
)
