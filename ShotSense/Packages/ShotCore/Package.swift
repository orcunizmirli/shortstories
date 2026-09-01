// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShotCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ShotCore", targets: ["ShotCore"])
    ],
    dependencies: [
        .package(path: "../AppFoundation")
    ],
    targets: [
        .target(name: "ShotCore", dependencies: ["AppFoundation"]),
        .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore"])
    ],
    swiftLanguageModes: [.v6]
)
