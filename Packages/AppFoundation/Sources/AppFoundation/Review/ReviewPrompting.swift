import Foundation

// Uygulama-içi App Store puanlama istemi (RTG-01; 00-genel-bakis.md §294: "SKStoreReviewController
// istemi YALNIZCA pozitif anlarda — bölüm bitirme + streak günü — tetiklenir; şikayet sinyali veren
// kullanıcıya önce destek akışı gösterilir"). Bu katman KARAR mantığını (ne zaman istenir) saf/test-
// edilebilir tutar; gerçek `SKStoreReviewController`/`requestReview` çağrısı `ReviewRequesting` portunun
// App-katmanı impl'indedir (StoreKit/UIKit AppFoundation'a sızmaz).

/// Puanlama istemini tetikleyebilecek POZİTİF an. (Negatif/şikayet anlarında ASLA çağrılmaz — çağıran
/// yalnız bu olaylarda `recordPositiveMoment` çağırır; destek akışı ayrı yüzeydir.)
public enum ReviewPromptTrigger: Sendable, Equatable {
    /// Bir bölüm sonuna kadar izlendi (bağlamsal auto-advance öncesi tamamlanma).
    case episodeCompleted
    /// Günlük check-in streak günü kazanıldı.
    case streakDay
}

/// Sistem puanlama istemini SUNAN port. Live impl (App) `SKStoreReviewController.requestReview(in:)`
/// / SwiftUI `RequestReviewAction` çağırır (ana thread'de); test/mock çağrıyı kaydeder.
public protocol ReviewRequesting: Sendable {
    @MainActor
    func requestReview()
}

/// Puanlama istemi KARAR politikası (saf; test-edilebilir). Apple zaten sistem istemini yılda ~3 ile
/// sınırlar ve gösterip göstermemeye kendisi karar verir — bu politika UYGULAMANIN KENDİ isteğini
/// terbiyeli tutar: yeterli etkileşim öncesi isteme, aynı sürümde tekrar isteme, iki istem arasında
/// asgari süre bırak.
public struct ReviewPromptPolicy: Sendable, Equatable {
    /// İlk istemden önce gereken asgari pozitif-an sayısı (yeni/az-etkileşimli kullanıcıyı rahatsız etme).
    public let minPositiveMoments: Int
    /// İki istem arasında (kendi isteğimiz) asgari gün (sürüm değişse bile spam olmasın).
    public let minDaysBetweenPrompts: Int
    /// Bir negatif sinyalden (oynatma hatası / başarısız satın alma) sonra istem bastırma penceresi (gün).
    /// Şikayet sinyali veren kullanıcıya istem gösterilmez; önce destek akışı önceliklenir (RTG-01 kriter 3).
    public let negativeSignalSuppressionDays: Int

    public init(
        minPositiveMoments: Int = 3,
        minDaysBetweenPrompts: Int = 120,
        negativeSignalSuppressionDays: Int = 14
    ) {
        self.minPositiveMoments = minPositiveMoments
        self.minDaysBetweenPrompts = minDaysBetweenPrompts
        self.negativeSignalSuppressionDays = negativeSignalSuppressionDays
    }

    /// Bu pozitif anda sistem istemi TALEP edilmeli mi?
    public func shouldRequest(
        positiveMomentCount: Int,
        state: ReviewPromptState,
        currentVersion: String,
        now: Date
    ) -> Bool {
        guard positiveMomentCount >= minPositiveMoments else {
            return false // yeterli etkileşim yok
        }
        if let lastPromptVersion = state.lastPromptVersion, lastPromptVersion == currentVersion {
            return false // bu sürümde zaten istendi
        }
        if let lastPromptAt = state.lastPromptAt {
            let elapsedDays = now.timeIntervalSince(lastPromptAt) / 86400
            // Negatif elapsed (cihaz saati geri alındı) da guard'lanır: < eşik → isteme.
            if elapsedDays < Double(minDaysBetweenPrompts) {
                return false // son istemden bu yana yeterli süre geçmedi
            }
        }
        if let lastNegativeSignalAt = state.lastNegativeSignalAt {
            let sinceNegative = now.timeIntervalSince(lastNegativeSignalAt) / 86400
            // Pencere içinde (ve gelecekteki damga = saat-kayması da) bastır → önce destek akışı.
            if sinceNegative < Double(negativeSignalSuppressionDays) {
                return false // yakın zamanda negatif sinyal → istem bastırılır
            }
        }
        return true
    }
}

/// Politikanın danıştığı KALICI durum (parametre kümesi). Son istem damgası + son negatif sinyal.
public struct ReviewPromptState: Sendable, Equatable {
    public let lastPromptAt: Date?
    public let lastPromptVersion: String?
    public let lastNegativeSignalAt: Date?

    public init(
        lastPromptAt: Date? = nil,
        lastPromptVersion: String? = nil,
        lastNegativeSignalAt: Date? = nil
    ) {
        self.lastPromptAt = lastPromptAt
        self.lastPromptVersion = lastPromptVersion
        self.lastNegativeSignalAt = lastNegativeSignalAt
    }
}

/// Puanlama istemini pozitif anlara bağlayan koordinatör. Durum (pozitif-an sayacı + son-istem damgası)
/// `PreferencesStoring`'de kalıcıdır; her pozitif anda politika danışılır, uygunsa port çağrılır.
/// @MainActor: pozitif anlar (bölüm bitişi / check-in) UI-güdümlüdür ve `requestReview` ana thread ister.
@MainActor
public final class ReviewPromptController {
    private let requester: any ReviewRequesting
    private let preferences: any PreferencesStoring
    private let policy: ReviewPromptPolicy
    private let currentAppVersion: String

    private static let countKey = PreferenceKey(name: "review.positive_moment_count", default: 0)
    /// `timeIntervalSince1970`; 0 = hiç istenmedi (Date PreferenceValue değil → Double saklanır).
    private static let lastAtKey = PreferenceKey(name: "review.last_prompt_at", default: 0.0)
    private static let lastVersionKey = PreferenceKey(name: "review.last_prompt_version", default: "")
    /// Son negatif sinyal (oynatma hatası / başarısız satın alma) damgası; 0 = yok.
    private static let lastNegativeAtKey = PreferenceKey(name: "review.last_negative_signal_at", default: 0.0)

    public init(
        requester: any ReviewRequesting,
        preferences: any PreferencesStoring,
        currentAppVersion: String,
        policy: ReviewPromptPolicy = ReviewPromptPolicy()
    ) {
        self.requester = requester
        self.preferences = preferences
        self.currentAppVersion = currentAppVersion
        self.policy = policy
    }

    /// Pozitif bir an (bölüm bitirme / streak günü) kaydeder: sayacı artırır (kalıcı) ve politika
    /// uygunsa sistem puanlama istemini talep edip son-istem damgasını yazar. Sistem istemi GERÇEKTEN
    /// talep edildiyse `true` döner → çağıran "istek" düzeyinde analitik (RTG-01 kriter 5) yazabilir
    /// (Apple diyaloğu gerçekten gösterip göstermediğini garanti etmez; event yalnız TALEBİ kaydeder).
    @discardableResult
    public func recordPositiveMoment(_ trigger: ReviewPromptTrigger, now: Date = Date()) -> Bool {
        _ = trigger // her iki tetik de "pozitif an"dır; ayrım gelecekteki analitik/eşik içindir
        let newCount = preferences.value(for: Self.countKey) + 1
        preferences.set(newCount, for: Self.countKey)

        let lastAtRaw = preferences.value(for: Self.lastAtKey)
        let lastPromptAt: Date? = lastAtRaw > 0 ? Date(timeIntervalSince1970: lastAtRaw) : nil
        let lastVersionRaw = preferences.value(for: Self.lastVersionKey)
        let lastPromptVersion: String? = lastVersionRaw.isEmpty ? nil : lastVersionRaw
        let lastNegativeRaw = preferences.value(for: Self.lastNegativeAtKey)
        let lastNegativeSignalAt: Date? = lastNegativeRaw > 0 ? Date(timeIntervalSince1970: lastNegativeRaw) : nil

        let state = ReviewPromptState(
            lastPromptAt: lastPromptAt,
            lastPromptVersion: lastPromptVersion,
            lastNegativeSignalAt: lastNegativeSignalAt
        )
        guard policy.shouldRequest(
            positiveMomentCount: newCount,
            state: state,
            currentVersion: currentAppVersion,
            now: now
        ) else {
            return false
        }

        requester.requestReview()
        preferences.set(now.timeIntervalSince1970, for: Self.lastAtKey)
        preferences.set(currentAppVersion, for: Self.lastVersionKey)
        return true
    }

    /// Negatif sinyal (oynatma hatası / başarısız satın alma) kaydeder → sonraki
    /// `negativeSignalSuppressionDays` boyunca puanlama istemi bastırılır (RTG-01 kriter 3: şikayet
    /// sinyali verene önce destek akışı). Kalıcı damga → app-kill'e dayanıklı.
    public func recordNegativeSignal(now: Date = Date()) {
        preferences.set(now.timeIntervalSince1970, for: Self.lastNegativeAtKey)
    }
}
