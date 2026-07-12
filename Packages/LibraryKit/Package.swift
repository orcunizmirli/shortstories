// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibraryKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "LibraryKit", targets: ["LibraryKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../DesignSystem"),
        .package(path: "../ContentKit"),
        .package(path: "../AnalyticsKit")
    ],
    targets: [
        .target(name: "LibraryKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
            .product(name: "DesignSystem", package: "DesignSystem"),
            .product(name: "ContentKit", package: "ContentKit"),
            .product(name: "AnalyticsKit", package: "AnalyticsKit")
        ]),
        .testTarget(name: "LibraryKitTests", dependencies: [
            "LibraryKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation")
        ])
    ],
    swiftLanguageModes: [.v6]
)
