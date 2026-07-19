import Foundation

/// Win-back teklif yüzeyinin A/B varyantı (SS-099 → SS-154). Deney ataması App katmanında
/// `ExperimentReading`'ten okunur; WalletKit bu YEREL değeri ENJEKTE alır (AnalyticsKit/FlagStore
/// doğrudan import EDİLMEZ — R kuralı). Varyant hem görünürlüğü (holdout) hem mesaj/treatment'ı
/// seçer (07 §7 "holdout ölçüm").
public enum WinBackVariant: String, Sendable, Equatable, CaseIterable {
    /// Kontrol/holdout — yüzey GÖSTERİLMEZ (lift ölçümü için; 07 §7).
    case control
    /// İndirimli dönüş fiyatı vurgulu treatment (win-back offer öne çıkar).
    case discount
    /// Yumuşak hatırlatma treatment'ı (fiyat vurgusu yok).
    case reminder
}

/// Yüzeyin gösterim frekansı durumu — App kalıcılıktan ENJEKTE eder (07 §5.3 tavan). Bu değer
/// istemcide MUTASYONA uğramaz; yüzey yalnız OKUR ve karar verir, sayaç artışını App yapar.
public struct WinBackFrequency: Sendable, Equatable {
    /// Bu yüzeyin en son gösterildiği an (`nil` → hiç gösterilmedi).
    public let lastShownAt: Date?
    /// Bugüne dek toplam gösterim sayısı.
    public let shownCount: Int

    public init(lastShownAt: Date?, shownCount: Int) {
        self.lastShownAt = lastShownAt
        self.shownCount = shownCount
    }

    /// Hiç gösterilmemiş başlangıç durumu.
    public static let fresh = WinBackFrequency(lastShownAt: nil, shownCount: 0)
}

/// Frekans tavanı politikası (07 §5.3 — tüm limitler remote-config'te; App sunucu değerlerini
/// enjekte edebilir). Buradaki `default` istemci-taraflı guardrail placeholder'ıdır.
public struct WinBackFrequencyPolicy: Sendable, Equatable {
    /// Toplam gösterim tavanı (bu sayıya ulaşınca artık gösterilmez).
    public let maxShows: Int
    /// Ardışık iki gösterim arasındaki minimum süre (saniye).
    public let minInterval: TimeInterval

    public init(maxShows: Int, minInterval: TimeInterval) {
        self.maxShows = maxShows
        self.minInterval = minInterval
    }

    /// İstemci guardrail varsayılanı: en çok 3 kez, gösterimler arası ≥ 24 saat. Sunucu remote
    /// config'i (07 §5.3) bunu override edebilir; kesin tavan backend'de uygulanır.
    public static let `default` = WinBackFrequencyPolicy(maxShows: 3, minInterval: 24 * 3600)

    /// Frekans tavanı `now` itibarıyla yeni bir gösterime izin veriyor mu?
    func allows(_ frequency: WinBackFrequency, now: Date) -> Bool {
        guard frequency.shownCount < maxShows else { return false }
        if let last = frequency.lastShownAt, now.timeIntervalSince(last) < minInterval {
            return false
        }
        return true
    }
}

/// VIP win-back teklif yüzeyinin görünürlük + mesaj KARARI (SS-099 F2) — SAF, deterministik,
/// izole test. Görünürlük dört kapıdan geçer (hepsi gerekli):
/// remote config açık (kill-switch) → uygunluk (`WinBackEligibility`) → varyant treatment (holdout
/// değil) → frekans tavanı (07 §5.3). Mesaj tek KAYNAKtır: View verbatim çizer, test doğrular
/// (`EarnedExpiryWarning` deseni). Pazarlama kopyası CMS'ten override edilebilir (07 §5.4); App
/// `variant`/`reason`/`offerDisplayPrice`'ı bunun için taşır.
public struct WinBackSurface: Sendable, Equatable {
    public let isVisible: Bool
    /// Görünürken seçilen treatment varyantı (holdout gizliyse `nil`).
    public let variant: WinBackVariant?
    /// Uygunluğu tetikleyen neden (mesaj bağlamı).
    public let reason: WinBackEligibility.Reason?
    /// Banda basılan Türkçe cümle (görünürken dolu; View verbatim çizer).
    public let message: String?
    /// Yalnız `discount` treatment'ta ve offer VARKEN dolu indirimli fiyat (06 §8.2 uygun olmayana
    /// / uygun olmayan treatment'a fiyat gösterme). Fiyat StoreKit'ten; hardcode YASAK.
    public let offerDisplayPrice: String?

    public init(
        isVisible: Bool,
        variant: WinBackVariant?,
        reason: WinBackEligibility.Reason?,
        message: String?,
        offerDisplayPrice: String?
    ) {
        self.isVisible = isVisible
        self.variant = variant
        self.reason = reason
        self.message = message
        self.offerDisplayPrice = offerDisplayPrice
    }

    /// Gizli yüzey (herhangi bir kapı kapalı).
    public static let hidden = WinBackSurface(
        isVisible: false,
        variant: nil,
        reason: nil,
        message: nil,
        offerDisplayPrice: nil
    )

    /// Görünürlük + mesaj kararı.
    ///
    /// - Parameters:
    ///   - eligibility: `WinBackEligibility.evaluate` sonucu (server-otoriter türev).
    ///   - remoteConfigEnabled: Remote config kill-switch — kapalıysa yüzey hiç çizilmez (09 F2:
    ///     "win-back teklif yüzeyi remote config ile açılıp kapanabiliyor").
    ///   - variant: Enjekte A/B varyant (SS-154). `.control` → holdout, gizli.
    ///   - frequency: Enjekte gösterim durumu (07 §5.3).
    ///   - policy: Frekans tavanı politikası (varsayılan istemci guardrail).
    ///   - offer: `WinBackOffer.resolve` çıktısı; `nil` → fiyatsız mesaj (06 §8.2).
    ///   - expiryDateText: App'in lokalize/timezone-doğru biçimlendirdiği bitiş tarihi metni
    ///     (yalnız `autoRenewOff` mesajında kullanılır; saf mantık locale biçimlemesi yapmaz).
    ///   - now: Enjekte "şimdi" (frekans penceresi için).
    public static func resolve(
        eligibility: WinBackEligibility,
        remoteConfigEnabled: Bool,
        variant: WinBackVariant,
        frequency: WinBackFrequency,
        policy: WinBackFrequencyPolicy = .default,
        offer: WinBackOffer? = nil,
        expiryDateText: String? = nil,
        now: Date
    ) -> WinBackSurface {
        // Kapı 1: remote config kill-switch.
        guard remoteConfigEnabled else { return .hidden }
        // Kapı 2: uygunluk (server-otoriter türev).
        guard case let .eligible(reason) = eligibility else { return .hidden }
        // Kapı 3: varyant treatment — holdout gizli.
        guard variant != .control else { return .hidden }
        // Kapı 4: frekans tavanı.
        guard policy.allows(frequency, now: now) else { return .hidden }

        let showsPrice = variant == .discount && offer != nil
        let message = message(reason: reason, variant: variant, offer: offer, expiryDateText: expiryDateText)
        return WinBackSurface(
            isVisible: true,
            variant: variant,
            reason: reason,
            message: message,
            offerDisplayPrice: showsPrice ? offer?.displayPrice : nil
        )
    }

    /// Mesaj bileşimi (tek kaynak). `autoRenewOff` → bitiş tarihi cümlesi (06 §8.2 "Aboneliğin
    /// {tarih}te sona erecek") + win-back eki; `formerVIP`/`serverSegment` → dönüş çağrısı. Fiyat
    /// YALNIZ `discount` treatment'ta ve offer varken cümleye girer — `reminder` fayda-odaklıdır,
    /// fiyat anmaz (A/B kontrastı). Uygun offer yoksa fiyatsız düşer (06 §8.2 "uygun olmayana
    /// gösterme"). `offerDisplayPrice` yapısal alanı da bu kuralla hizalıdır.
    static func message(
        reason: WinBackEligibility.Reason,
        variant: WinBackVariant,
        offer: WinBackOffer?,
        expiryDateText: String?
    ) -> String {
        let discountPrice = variant == .discount ? offer?.displayPrice : nil
        switch reason {
        case .autoRenewOff:
            let expiryClause = expiryDateText.map { "Aboneliğin \($0) tarihinde sona erecek." }
            let tail = discountPrice.map { "İndirimli fiyatla sürdür: \($0)." }
                ?? "VIP avantajlarını korumak için dilediğin an yenileyebilirsin."
            return [expiryClause, tail].compactMap(\.self).joined(separator: " ")
        case .formerVIP, .serverSegment:
            if let discountPrice {
                return "VIP'e indirimli dön: \(discountPrice)."
            }
            return "Seni özledik. VIP avantajları seni bekliyor."
        }
    }
}
