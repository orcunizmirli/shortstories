// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WalletKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "WalletKit", targets: ["WalletKit"])],
    dependencies: [
        // Çekirdek cüzdan/IAP mantığı yalnız AppFoundation'a bağlıdır (R2/R4); StoreKit tipleri
        // paket içinde hapsolur. DesignSystem + AnalyticsKit UI dilimiyle (UnlockSheet/
        // CoinMagazasi/VIPAbonelik) birlikte gelir: DS token/bileşenleri ve tipli analitik
        // yüzeyi yalnız `UI/` altındaki ekranlarca kullanılır.
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
