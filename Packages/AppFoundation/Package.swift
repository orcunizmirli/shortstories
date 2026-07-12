// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFoundation",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppFoundation", targets: ["AppFoundation"]),
        .library(name: "AppFoundationTestSupport", targets: ["AppFoundationTestSupport"]),
    ],
    targets: [
        .target(name: "AppFoundation"),
        .target(name: "AppFoundationTestSupport", dependencies: ["AppFoundation"]),
        .testTarget(name: "AppFoundationTests",
                    dependencies: ["AppFoundation", "AppFoundationTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
