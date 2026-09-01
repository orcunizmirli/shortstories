// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntelligenceKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "IntelligenceKit", targets: ["IntelligenceKit"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore")
    ],
    targets: [
        .target(name: "IntelligenceKit", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(name: "IntelligenceKitTests", dependencies: ["IntelligenceKit"])
    ],
    swiftLanguageModes: [.v6]
)
