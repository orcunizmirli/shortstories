// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OCRKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "OCRKit", targets: ["OCRKit"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore")
    ],
    targets: [
        .target(name: "OCRKit", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(name: "OCRKitTests", dependencies: ["OCRKit"])
    ],
    swiftLanguageModes: [.v6]
)
