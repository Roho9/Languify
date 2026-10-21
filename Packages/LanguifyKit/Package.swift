// swift-tools-version: 6.2
import PackageDescription

// LanguifyKit holds the platform-independent core of Languify: domain models,
// the rolling audio buffer, the listening state machine, spaced repetition,
// quotas, AI response contracts and the backend client. It deliberately avoids
// UIKit, SwiftUI, SwiftData and AVFoundation so it can be unit tested quickly
// on macOS with `swift test`.
let package = Package(
    name: "LanguifyKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LanguifyKit", targets: ["LanguifyKit"])
    ],
    targets: [
        .target(name: "LanguifyKit"),
        .testTarget(name: "LanguifyKitTests", dependencies: ["LanguifyKit"])
    ]
)
