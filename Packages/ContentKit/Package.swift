// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContentKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ContentKit", targets: ["ContentKit"])],
    dependencies: [
        .package(path: "../AppFoundation"),
    ],
    targets: [
        .target(name: "ContentKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
        ]),
        .testTarget(name: "ContentKitTests", dependencies: [
            "ContentKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
