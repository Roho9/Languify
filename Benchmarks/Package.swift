// swift-tools-version: 6.2
import PackageDescription

// Benchmark harness for Languify. Runs on macOS against the same LanguifyKit
// code the app ships, plus frozen baseline copies of code that was later
// optimised, so before/after comparisons stay reproducible.
let package = Package(
    name: "LanguifyBench",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../Packages/LanguifyKit")],
    targets: [
        .executableTarget(
            name: "LanguifyBench",
            dependencies: [.product(name: "LanguifyKit", package: "LanguifyKit")]
        ),
        .testTarget(name: "LanguifyBenchTests", dependencies: ["LanguifyBench", .product(name: "LanguifyKit", package: "LanguifyKit")]),
    ]
)
