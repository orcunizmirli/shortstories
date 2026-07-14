// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WalletKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "WalletKit", targets: ["WalletKit"])],
    dependencies: [
        // Yalnız AppFoundation: analitik `AnalyticsTracking` portundan (AppFoundation), StoreKit
        // tipleri paket içinde hapsolur. DesignSystem UI dilimiyle (UnlockSheet/CoinMagazasi)
        // birlikte gelir; çekirdek cüzdan/IAP mantığı ona bağlı değildir (R2/R4).
        .package(path: "../AppFoundation")
    ],
    targets: [
        .target(name: "WalletKit", dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation")
        ]),
        .testTarget(name: "WalletKitTests", dependencies: [
            "WalletKit",
            .product(name: "AppFoundationTestSupport", package: "AppFoundation")
        ])
    ],
    swiftLanguageModes: [.v6]
)
