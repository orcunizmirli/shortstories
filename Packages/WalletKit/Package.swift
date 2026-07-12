// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WalletKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "WalletKit", targets: ["WalletKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../DesignSystem"),
        .package(path: "../AnalyticsKit")
    ],
    targets: [
        .target(name: "WalletKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
            .product(name: "DesignSystem", package: "DesignSystem"),
            .product(name: "AnalyticsKit", package: "AnalyticsKit")
        ]),
        .testTarget(name: "WalletKitTests", dependencies: [
            "WalletKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation")
        ])
    ],
    swiftLanguageModes: [.v6]
)
