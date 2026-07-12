import AnalyticsKit
import AppFoundation
import DesignSystem

/// WalletKit — coin cüzdanı (WalletStore actor), StoreKit 2, entitlement;
/// UnlockSheet/CoinMagazasi/VIPAbonelik ekranları (KANON §4).
/// F1 kapsamı: SS-090…SS-099 (docs/09 §E9); fraud sinyalleri SS-100 F2.
/// ContentKit'e BAĞIMLI DEĞİLDİR (R3): içerik referansı `SeriesID`/`EpisodeID`
/// (AppFoundation/SharedTypes) ve `UnlockRequest` value geçirmesiyle (R5) taşınır.
public enum WalletKitModule {
    public static let name = "WalletKit"
}
