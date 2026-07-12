// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RewardsKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "RewardsKit", targets: ["RewardsKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../DesignSystem"),
        .package(path: "../AnalyticsKit")
    ],
    targets: [
        .target(name: "RewardsKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
            .product(name: "DesignSystem", package: "DesignSystem"),
            .product(name: "AnalyticsKit", package: "AnalyticsKit")
        ]),
        .testTarget(name: "RewardsKitTests", dependencies: [
            "RewardsKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation")
        ])
    ],
    swiftLanguageModes: [.v6]
)
