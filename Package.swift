// swift-tools-version: 5.9
// SwiftPM is used for the CLI only (`swift build -c release --product testbridge`).
// The macOS app is built through the XcodeGen project (project.yml).
import PackageDescription

let package = Package(
    name: "TestBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "testbridge", targets: ["testbridge"]),
        .library(name: "TestBridgeCore", targets: ["TestBridgeCore"]),
    ],
    targets: [
        .target(name: "TestBridgeCore", path: "Sources/TestBridgeCore"),
        .executableTarget(name: "testbridge", dependencies: ["TestBridgeCore"], path: "Sources/testbridge-cli"),
        .testTarget(name: "TestBridgeCoreTests", dependencies: ["TestBridgeCore"], path: "Tests/TestBridgeCoreTests"),
    ]
)
