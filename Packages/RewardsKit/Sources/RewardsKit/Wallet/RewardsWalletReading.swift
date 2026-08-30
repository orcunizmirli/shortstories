/// OdulMerkezi coin bakiyesi başlığının OKUMA portu (SS-110, R8). RewardsKit tanımlar (tüketici),
/// App canlı WalletKit'e bağlar (üretici) — RewardsKit WalletKit tipini (`CoinBalance`) GÖRMEZ.
/// Kalıp: ProfileKit `WalletSummaryReading`, LibraryKit `LibraryCatalogReading`.
///
/// Doğruluk kaynağı SUNUCUDUR (03 §9): başlık iyimser bir gösterimdir. Claim başarısında bakiye
/// `CheckInClaimResult.coinBalance` ile de güncellenir; bu akış başka cihazdan gelen değişimleri
/// (satın alma/VIP bonusu) OdulMerkezi açıkken yansıtır.
///
/// VERSİYON (audit MEDIUM applyBalance donması): akış+snapshot her değeri MONOTON `version` ile taşır
/// (WalletStore out-of-order guard'ı, 05 §2.5). OdulMerkezi yalnız STRICTLY-NEWER version'ı uygular →
/// bayat düşük değer (pre-claim replay) version'a göre düşürülür, MEŞRU düşüş (spend, daha yüksek version)
/// uygulanır. Value-heuristic (`>= awaited`) çoklu-stale ile meşru-spend'i ayıramadığından (kalıcı donma)
/// version-tabanlı ayrım kullanılır.
public struct RewardsBalanceUpdate: Sendable, Equatable {
    /// Anlık toplam coin bakiyesi (purchased + earned).
    public let balance: Int
    /// Monoton sürüm (WalletStore); yalnız daha büyük version uygulanır. Snapshot yoksa `Int.min`.
    public let version: Int

    public init(balance: Int, version: Int) {
        self.balance = balance
        self.version = version
    }
}

public protocol RewardsWalletReading: Sendable {
    /// Anlık toplam coin bakiyesi + version — ilk yüklemede başlık + version baseline için.
    func currentBalance() async -> RewardsBalanceUpdate

    /// Bakiye değişim akışı (balance + version); OdulMerkezi açıkken canlı güncelleme. Abone olunca
    /// mevcut değeri replay eder (geç abone güncel bakiyeyi kaçırmaz; version aynıysa OdulMerkezi düşürür).
    func balanceUpdates() -> AsyncStream<RewardsBalanceUpdate>
}
