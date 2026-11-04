// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BambooPulseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"]),
    ],
    targets: [
        .target(name: "PulseCore"),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"]),
    ]
)
