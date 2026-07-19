import Foundation

/// Sunucunun win-back segment kararı (07 §7 / 06 §5.1). Churn/segment kararı SERVER-OTORİTERdir
/// (`DID_CHANGE_RENEWAL_STATUS` + inaktivite sinyalinden backend hesaplar); istemci churn'e KARAR
/// VERMEZ — bu sinyal geldiğinde onu OTORİTE kabul eder. Sinyal yokken (`nil`) istemci yalnız
/// yerel entitlement'tan hızlı-yol türetir (≤5 sn tazeleme iyimserliği), sunucuyu asla EZMEZ.
public enum WinBackServerSignal: Sendable, Equatable {
    /// Backend kullanıcıyı win-back segmentine aldı → otoriter uygun.
    case eligible
    /// Backend dışladı: holdout (07 §7 ölçüm), velocity/fraud tavanı (07 §7.2), ya da zaten
    /// dönmüş kullanıcı → yerel tetikleyiciler ateşlense bile GÖSTERİLMEZ.
    case excluded
}

/// VIP win-back teklif yüzeyinin uygunluk kararı (SS-099 F2) — SAF, yan etkisiz, `now` enjekte
/// edilebilir → izole, deterministik test. Churn/segment SERVER-OTORİTERdir; bu tip bakiyeye
/// dokunmaz, yalnız hangi yüzeyin/mesajın uygun olduğunu türetir (istemci gösterir, karar vermez).
///
/// Kaynak modeli `SubscriptionStatus`'tur (05 §2.8 — doğruluk kaynağı SUNUCU): win-back kuralları
/// `willAutoRenew` + `expiresAt` gerektirir ve bu alanlar YALNIZ `SubscriptionStatus`'ta bulunur
/// (`EntitlementSnapshot` push-refresh yükü auto-renew taşımaz).
public enum WinBackEligibility: Sendable, Equatable {
    case eligible(Reason)
    case ineligible

    /// Uygunluğu tetikleyen neden — yüzey mesaj/treatment seçiminde kullanılır.
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        /// Sunucu win-back segmenti (otoriter).
        case serverSegment
        /// Eski VIP: abonelik sona ermiş/iptal, üzerinden 7+ gün geçmiş (07 §7).
        case formerVIP
        /// Hâlâ VIP ama auto-renew kapalı, dönem sonuna yaklaşıyor — churn-risk (06 §5.1/§8.3).
        case autoRenewOff
    }

    /// Eski VIP kuralının gün eşiği (07 §7: "7+ gün geçmiş"). Remote-config ile ayarlanabilir;
    /// çağrı başına override edilebilir.
    public static let defaultFormerVIPGraceDays = 7

    public var isEligible: Bool {
        if case .eligible = self {
            return true
        }
        return false
    }

    public var reason: Reason? {
        if case let .eligible(reason) = self {
            return reason
        }
        return nil
    }

    /// Uygunluk kararı. Sıra:
    /// 1. Sunucu sinyali varsa OTORİTEdir (istemci churn'e karar vermez): `.eligible` →
    ///    `.serverSegment`; `.excluded` → `.ineligible` (holdout/fraud/dönmüş).
    /// 2. Grace/billing-retry → win-back DEĞİL (06 §8.4 "ödeme yöntemini güncelle" banner'ı; erişim
    ///    sürüyor, churn değil).
    /// 3. Hâlâ VIP + auto-renew kapalı + dönem sonu gelecekte (opsiyonel `nearExpiryWindow` içinde)
    ///    → `.autoRenewOff` (06 §5.1/§8.3). Aktif, otomatik yenilenen VIP → `.ineligible`.
    /// 4. VIP değil + biten aboneliğin üzerinden `formerVIPGraceDays`+ gün geçmiş → `.formerVIP`
    ///    (07 §7). Daha taze churn (7 günden az) henüz uygun değildir.
    ///
    /// - Parameters:
    ///   - subscription: Sunucu-otoriter abonelik durumu (isVIP/expiresAt/willAutoRenew/grace).
    ///   - serverSignal: Backend win-back segment kararı; `nil` → yalnız yerel hızlı-yol.
    ///   - now: Enjekte edilen "şimdi" (izole test).
    ///   - formerVIPGraceDays: Eski VIP gün eşiği (varsayılan 7; 07 §7).
    ///   - nearExpiryWindow: `autoRenewOff` için dönem sonuna yakınlık penceresi (saniye). `nil` →
    ///     kalan tüm dönem uygundur (06 §8.3 "auto-renew kapalıysa göster"); verilirse yalnız
    ///     `expiresAt <= now + pencere` iken tetiklenir (task "dönem sonuna yakın").
    public static func evaluate(
        subscription: SubscriptionStatus,
        serverSignal: WinBackServerSignal?,
        now: Date,
        formerVIPGraceDays: Int = defaultFormerVIPGraceDays,
        nearExpiryWindow: TimeInterval? = nil
    ) -> WinBackEligibility {
        // 1. Sunucu otoritesi (varsa) her şeyi ezer.
        if let serverSignal {
            switch serverSignal {
            case .eligible: return .eligible(.serverSegment)
            case .excluded: return .ineligible
            }
        }

        // 2. Grace/billing-retry churn değildir (06 §8.4) — win-back değil.
        if subscription.isInGracePeriod {
            return .ineligible
        }

        // 3. Hâlâ VIP: yalnız auto-renew kapalıysa ve dönem sonu gelecekteyse churn-risk.
        if subscription.isVIP {
            guard !subscription.willAutoRenew, let expiry = subscription.expiresAt, expiry > now else {
                return .ineligible
            }
            if let window = nearExpiryWindow, expiry > now.addingTimeInterval(window) {
                return .ineligible // henüz dönem sonuna "yakın" değil
            }
            return .eligible(.autoRenewOff)
        }

        // 4. Eski VIP: biten aboneliğin üzerinden formerVIPGraceDays+ gün geçti mi?
        if let expiry = subscription.expiresAt {
            let cutoff = expiry.addingTimeInterval(TimeInterval(formerVIPGraceDays) * 86400)
            if now >= cutoff {
                return .eligible(.formerVIP)
            }
        }
        return .ineligible
    }
}
