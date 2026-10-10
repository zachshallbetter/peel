// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeelKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PeelKit", targets: ["PeelKit"]),
    ],
    targets: [
        .target(
            name: "PeelKit",
            path: "Sources/PeelKit"
        ),
        .testTarget(
            name: "PeelKitTests",
            dependencies: ["PeelKit"],
            path: "Tests/PeelKitTests"
        ),
    ]
)
