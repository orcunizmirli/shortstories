// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnalyticsKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "AnalyticsKit", targets: ["AnalyticsKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
    ],
    targets: [
        .target(name: "AnalyticsKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
        ]),
        .testTarget(name: "AnalyticsKitTests", dependencies: [
            "AnalyticsKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
