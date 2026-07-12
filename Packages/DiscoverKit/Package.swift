// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiscoverKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "DiscoverKit", targets: ["DiscoverKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../DesignSystem"),
        .package(path: "../ContentKit"),
        .package(path: "../AnalyticsKit"),
    ],
    targets: [
        .target(name: "DiscoverKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
            .product(name: "DesignSystem", package: "DesignSystem"),
            .product(name: "ContentKit", package: "ContentKit"),
            .product(name: "AnalyticsKit", package: "AnalyticsKit"),
        ]),
        .testTarget(name: "DiscoverKitTests", dependencies: [
            "DiscoverKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
