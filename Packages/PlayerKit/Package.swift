// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlayerKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PlayerKit", targets: ["PlayerKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../DesignSystem"),
        .package(path: "../ContentKit"),
        .package(path: "../AnalyticsKit")
    ],
    targets: [
        .target(name: "PlayerKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
            .product(name: "DesignSystem", package: "DesignSystem"),
            .product(name: "ContentKit", package: "ContentKit"),
            .product(name: "AnalyticsKit", package: "AnalyticsKit")
        ]),
        .testTarget(name: "PlayerKitTests", dependencies: [
            "PlayerKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation")
        ])
    ],
    swiftLanguageModes: [.v6]
)
