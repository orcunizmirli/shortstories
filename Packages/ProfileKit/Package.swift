// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProfileKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ProfileKit", targets: ["ProfileKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../DesignSystem"),
        .package(path: "../AnalyticsKit")
    ],
    targets: [
        .target(name: "ProfileKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
            .product(name: "DesignSystem", package: "DesignSystem"),
            .product(name: "AnalyticsKit", package: "AnalyticsKit")
        ]),
        .testTarget(name: "ProfileKitTests", dependencies: [
            "ProfileKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation")
        ])
    ],
    swiftLanguageModes: [.v6]
)
