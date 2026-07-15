import Foundation

/// Profil hesap/cüzdan satırının ihtiyaç duyduğu cüzdan özeti — SAF değer tipi. ProfileKit
/// WalletKit tiplerini (`CoinBalance`/`SubscriptionStatus`) GÖRMEZ (R2); App bir adaptörle
/// WalletKit `WalletGateway`'ini bu dar yüzeye map eder.
public struct WalletSummary: Sendable, Equatable {
    /// Kullanıcıya gösterilen toplam coin (purchased+earned). Negatifse View 0'a kırpar
    /// (`DSCoinLabel` zaten kırpar); iade sonrası eksi bakiye satın-alma satırında ele alınır.
    public let coinBalance: Int
    /// VIP aktif mi (satır "VIP'e geç" tanıtımı ↔ "plan + yenileme" yönetimi arasında seçer).
    public let isVIP: Bool
    /// VIP ise yenileme/bitiş tarihi (yönetim satırı); değilse `nil`.
    public let vipRenewalDate: Date?

    public init(coinBalance: Int, isVIP: Bool, vipRenewalDate: Date?) {
        self.coinBalance = coinBalance
        self.isVIP = isVIP
        self.vipRenewalDate = vipRenewalDate
    }

    public static let empty = WalletSummary(coinBalance: 0, isVIP: false, vipRenewalDate: nil)
}

/// Profil'in cüzdan bakiyesi + VIP durumu OKUMA portu (SS-130, R8). ProfileKit tanımlar (tüketici),
/// App canlı WalletKit'e bağlar (üretici) — LibraryKit `LibraryCatalogReading` kalıbıyla birebir.
/// Doğruluk kaynağı sunucudur; bu iyimser UI ipucudur (Profil cache-first, 02 §4.13).
public protocol WalletSummaryReading: Sendable {
    /// Anlık cüzdan özeti (ilk yüklemede).
    func currentSummary() async -> WalletSummary

    /// Bakiye/VIP değişim akışı; Profil açıkken canlı güncelleme. Abone olunca mevcut değeri
    /// replay eder (başka cihazdan satın alma/VIP aktivasyonu anında yansısın).
    func summaryUpdates() -> AsyncStream<WalletSummary>
}
