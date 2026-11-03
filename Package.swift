// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StockNotch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "StockNotch"),
        .testTarget(name: "StockNotchTests", dependencies: ["StockNotch"]),
    ]
)
