/// OdulMerkezi coin bakiyesi başlığının OKUMA portu (SS-110, R8). RewardsKit tanımlar (tüketici),
/// App canlı WalletKit'e bağlar (üretici) — RewardsKit WalletKit tipini (`CoinBalance`) GÖRMEZ.
/// Kalıp: ProfileKit `WalletSummaryReading`, LibraryKit `LibraryCatalogReading`.
///
/// Doğruluk kaynağı SUNUCUDUR (03 §9): başlık iyimser bir gösterimdir. Claim başarısında bakiye
/// `CheckInClaimResult.coinBalance` ile de güncellenir; bu akış başka cihazdan gelen değişimleri
/// (satın alma/VIP bonusu) OdulMerkezi açıkken yansıtır.
public protocol RewardsWalletReading: Sendable {
    /// Anlık toplam coin bakiyesi (purchased + earned) — ilk yüklemede başlık için.
    func currentBalance() async -> Int

    /// Bakiye değişim akışı; OdulMerkezi açıkken canlı güncelleme. Abone olunca mevcut değeri
    /// replay eder (geç abone güncel bakiyeyi kaçırmaz).
    func balanceUpdates() -> AsyncStream<Int>
}
