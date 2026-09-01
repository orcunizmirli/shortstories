// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFoundation",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AppFoundation", targets: ["AppFoundation"])
    ],
    targets: [
        .target(name: "AppFoundation"),
        .testTarget(name: "AppFoundationTests", dependencies: ["AppFoundation"])
    ],
    swiftLanguageModes: [.v6]
)
