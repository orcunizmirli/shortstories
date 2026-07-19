import Foundation

/// VIP win-back yüzeyinin App-enjekte konfigürasyonu (SS-099 F2) — `VIPSubscriptionModel`'in
/// win-back kararını beslediği DAR seam. WalletKit AnalyticsKit deney istemcisini / App
/// `FeatureFlagStore`'unu import ETMEZ (R kuralı); App kompozisyon kökünde bu DÜZ değerleri bağlar:
/// remote-config kill-switch (FeatureFlagStore), SS-154 A/B varyantı (`ExperimentReading` →
/// yerel `WinBackVariant`), backend segment sinyali, frekans durumu (kalıcılıktan) ve
/// locale/timezone-doğru tarih biçimleyici (saf mantık biçimlemez).
///
/// Varsayılan `.disabled` → remote config KAPALI → yüzey hiç çizilmez ve mevcut VIPAbonelik
/// davranışı birebir korunur (geriye uyumlu; App bağlamadıkça banner yok).
public struct WinBackConfiguration: Sendable {
    /// Remote-config kill-switch (09 F2 "win-back teklif yüzeyi remote config ile açılıp
    /// kapanabiliyor"). Kapalı → banner hiç çizilmez.
    public var isRemoteConfigEnabled: Bool
    /// SS-154 A/B varyantı (App `ExperimentReading` atamasını `WinBackVariant`'a map eder).
    /// `.control` → holdout, gizli (07 §7 lift ölçümü).
    public var variant: WinBackVariant
    /// Backend win-back segment sinyali — varsa OTORİTE (07 §7 / 06 §5.1); `nil` → yalnız yerel
    /// entitlement türetimi (istemci churn'e karar vermez).
    public var serverSignal: WinBackServerSignal?
    /// Gösterim frekansı durumu — App kalıcılıktan enjekte eder (07 §5.3 tavan). Yüzey yalnız OKUR;
    /// sayaç artışını App persist eder (bkz. `onBannerShown`).
    public var frequency: WinBackFrequency
    /// Frekans tavanı politikası (07 §5.3; App remote-config değerlerini enjekte edebilir).
    public var policy: WinBackFrequencyPolicy
    /// `autoRenewOff` için dönem-sonuna yakınlık penceresi (saniye). `nil` → kalan tüm dönem uygun.
    public var nearExpiryWindow: TimeInterval?
    /// Eski VIP gün eşiği (07 §7 "7+ gün geçmiş"; varsayılan 7). Remote-config'ten override edilebilir.
    public var formerVIPGraceDays: Int
    /// Enjekte "şimdi" — uygunluk + frekans değerlendirmesi için (izole, deterministik test).
    public var now: @Sendable () -> Date
    /// Bitiş tarihini locale/timezone-doğru biçimleyen App kapanışı (yalnız `autoRenewOff` mesajında;
    /// saf `WinBackSurface` mantığı locale biçimlemesi yapmaz — 06 §8.2 "Aboneliğin {tarih}te...").
    public var expiryDateFormatter: @Sendable (Date) -> String
    /// Banner bu ekran ömründe İLK kez görünürken App'e haber — frekans sayacını App persist eder
    /// (07 §5.3; yüzey saf kalır, mutasyon yapmaz). Varyant + neden, CMS/analitik bağlamı için taşınır.
    public var onBannerShown: (@Sendable (WinBackVariant, WinBackEligibility.Reason) -> Void)?

    public init(
        isRemoteConfigEnabled: Bool = false,
        variant: WinBackVariant = .control,
        serverSignal: WinBackServerSignal? = nil,
        frequency: WinBackFrequency = .fresh,
        policy: WinBackFrequencyPolicy = .default,
        nearExpiryWindow: TimeInterval? = nil,
        formerVIPGraceDays: Int = WinBackEligibility.defaultFormerVIPGraceDays,
        now: @escaping @Sendable () -> Date = { Date() },
        expiryDateFormatter: @escaping @Sendable (Date) -> String = { $0.formatted(date: .long, time: .omitted) },
        onBannerShown: (@Sendable (WinBackVariant, WinBackEligibility.Reason) -> Void)? = nil
    ) {
        self.isRemoteConfigEnabled = isRemoteConfigEnabled
        self.variant = variant
        self.serverSignal = serverSignal
        self.frequency = frequency
        self.policy = policy
        self.nearExpiryWindow = nearExpiryWindow
        self.formerVIPGraceDays = formerVIPGraceDays
        self.now = now
        self.expiryDateFormatter = expiryDateFormatter
        self.onBannerShown = onBannerShown
    }

    /// Kapalı varsayılan: remote config OFF → yüzey hiç çizilmez (mevcut VIP davranışı korunur).
    public static let disabled = WinBackConfiguration()
}
