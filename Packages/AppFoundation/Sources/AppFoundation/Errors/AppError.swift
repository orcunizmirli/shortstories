import Foundation

/// Uygulama genelinde katman sınırından geçebilen TEK hata tipi (03-mimari.md §10.1).
/// Feature'lar kendi alt-error tiplerini tanımlayıp `AppError`'a sarar; "düz" `Error`
/// katman sınırından geçemez — sınırda mutlaka `AppError`'a map edilir.
public enum AppError: Error, Sendable, Equatable {
    case network(NetworkError)
    case auth(AuthError)
    case playback(PlaybackError)
    case wallet(WalletError)
    case content(ContentError)
    case storage(StorageError)
    case featureDisabled(flag: String)
    case unexpected(underlying: String)
}

public enum NetworkError: Sendable, Equatable {
    case offline
    case timeout
    case server(status: Int)
    case decoding
}

public enum AuthError: Sendable, Equatable {
    case sessionExpired
    case linkingFailed
    case guestBootstrapFailed
}

/// Detaylı davranış: 04-player-engine.md.
public enum PlaybackError: Sendable, Equatable {
    case assetUnavailable
    case drmDenied
    case signedURLExpired
}

/// StoreKit 2 satın alma sonucunun taşıma-bağımsız özeti. StoreKit tipleri `WalletKit`'te
/// hapsolur (R6); bu enum yalnız hata bağlamı taşımak içindir.
public enum StoreKitStatus: String, Sendable, Equatable {
    case userCancelled
    case pending
    case verificationFailed
    case unknown
}

public enum WalletError: Sendable, Equatable {
    /// 402 INSUFFICIENT_COINS (05 §4.5): `details.shortfall` = eksik kalan coin. Sunucu gövdesi
    /// zenginse dolu; kod-yoksa/ham-yolda `nil` (çağıran snapshot'tan türetir).
    case insufficientCoins(shortfall: Int?)
    /// 409 PRICE_CHANGED (05 §4.5): `details.currentPrice` = güncel açma fiyatı. UnlockSheet
    /// fiyatı bununla güncellenir; otomatik harcama yapılmaz.
    case priceChanged(currentPrice: Int?)
    /// 409 RECEIPT_ALREADY_PROCESSED (05 §10.2): `details.original` = orijinal transaction kimliği
    /// (idempotent tekrar). Akış başarı sayar; transaction finish edilir.
    case receiptAlreadyProcessed(originalTransactionID: String?)
    /// 422 RECEIPT_INVALID (05 §4.6): sahte/doğrulanamayan receipt — transaction finish EDİLMEZ,
    /// destek akışına yönlendirilir.
    case receiptInvalid
    case purchaseFailed(StoreKitStatus)
    case receiptValidationFailed
    case transactionConflict
}

public enum ContentError: Sendable, Equatable {
    case notFound
    case regionBlocked
    /// 403 + `EPISODE_LOCKED` (05 §10.2): kilitli bölüm. UnlockSheet'in TEK istekle
    /// açılması kabul kriteri, ilişkili `details` yüküne dayanır (fiyat + bakiye; 05 §4.4).
    case episodeLocked(EpisodeLockDetails)
    case episodeLockedStateStale
}

/// `403 EPISODE_LOCKED` yanıtındaki `details` yükü (05 §4.4): UnlockSheet ekstra round-trip
/// olmadan bu alanlarla açılır. `unlockPrice == nil` = coin yolu kapalı kilit
/// (05 §2.2 genişleme noktası; salt-VIP içerik).
public struct EpisodeLockDetails: Decodable, Sendable, Equatable {
    /// Görüntüleme amaçlı bakiye anlık görüntüsü; doğruluk kaynağı SUNUCUDUR (03 §9).
    public struct WalletSnapshot: Decodable, Sendable, Equatable {
        public let purchasedCoins: Int
        public let earnedCoins: Int

        public init(purchasedCoins: Int, earnedCoins: Int) {
            self.purchasedCoins = purchasedCoins
            self.earnedCoins = earnedCoins
        }
    }

    /// Coin ile açma fiyatı; `nil` = coin yolu kapalı (UnlockSheet coin satırını çizmez).
    public let unlockPrice: Int?
    /// Rewarded ad ile açılabilir mi (günlük cap sunucuda).
    public let adUnlockEligible: Bool
    public let wallet: WalletSnapshot?

    public init(unlockPrice: Int?, adUnlockEligible: Bool, wallet: WalletSnapshot?) {
        self.unlockPrice = unlockPrice
        self.adUnlockEligible = adUnlockEligible
        self.wallet = wallet
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unlockPrice = try container.decodeIfPresent(Int.self, forKey: .unlockPrice)
        // Alan yoksa güvenli varsayılan: reklam seçeneği gösterilmez.
        adUnlockEligible = try container.decodeIfPresent(Bool.self, forKey: .adUnlockEligible) ?? false
        wallet = try container.decodeIfPresent(WalletSnapshot.self, forKey: .wallet)
    }

    private enum CodingKeys: String, CodingKey {
        case unlockPrice
        case adUnlockEligible
        case wallet
    }
}

public enum StorageError: Sendable, Equatable {
    case migrationFailed
    case diskFull
    case keychainUnavailable
}

public extension AppError {
    /// Otomatik retry'a uygun mu (03 §8.3 tablosu): 5xx/429, timeout ve bağlantı
    /// kopması retryable'dır; diğer 4xx, auth ve cüzdan hataları DEĞİLDİR.
    var isRetryable: Bool {
        switch self {
        case let .network(error):
            switch error {
            case .offline, .timeout:
                true
            case let .server(status):
                status >= 500 || status == 429
            case .decoding:
                false
            }
        case let .playback(error):
            error == .signedURLExpired
        case .auth, .wallet, .content, .storage, .featureDisabled, .unexpected:
            false
        }
    }

    /// Kullanıcıya gösterilebilir mesaj; kullanıcıya hiç gösterilmeyen arka plan
    /// hataları için `nil` (gösterim stratejisi: 03 §10.2).
    var userFacingMessage: LocalizedStringResource? {
        switch self {
        case let .network(error):
            switch error {
            case .offline:
                "You're offline. Check your connection and try again."
            case .timeout:
                "The connection timed out. Please try again."
            case .server:
                "Something went wrong on our side. Please try again."
            case .decoding:
                "Something went wrong. Please try again."
            }
        case let .auth(error):
            switch error {
            case .sessionExpired:
                "Your session has expired. Please try again."
            case .linkingFailed:
                "We couldn't link your account. Please try again."
            case .guestBootstrapFailed:
                "We couldn't set up your account. Check your connection and try again."
            }
        case let .playback(error):
            switch error {
            case .assetUnavailable:
                "This episode can't be played right now."
            case .drmDenied:
                "This content can't be played on this device."
            case .signedURLExpired:
                nil // player katmanı URL'i sessizce tazeler
            }
        case let .wallet(error):
            switch error {
            case .insufficientCoins:
                // "Hata" değil akıştır: CoinMagazasi'na yönlendirir (03 §10.2)
                "You don't have enough coins."
            case .priceChanged:
                // Akış: UnlockSheet fiyatı sessizce güncellenir, generic uyarı gösterilmez.
                nil
            case .receiptAlreadyProcessed:
                // Başarı sayılır (idempotent tekrar): kullanıcıya hata gösterilmez.
                nil
            case .receiptInvalid:
                "We couldn't verify this purchase. Please contact support."
            case let .purchaseFailed(status):
                switch status {
                case .userCancelled:
                    nil
                case .pending:
                    "Your purchase is still processing. Your coins will arrive shortly."
                case .verificationFailed, .unknown:
                    "The purchase couldn't be completed. Please try again."
                }
            case .receiptValidationFailed:
                "We're verifying your purchase. Your coins will be added shortly."
            case .transactionConflict:
                "This transaction was already processed."
            }
        case let .content(error):
            switch error {
            case .notFound:
                "This content is no longer available."
            case .regionBlocked:
                "This content isn't available in your region."
            case .episodeLocked:
                // "Hata" değil akıştır: UnlockSheet açılır (05 §10.2), mesaj gösterilmez.
                nil
            case .episodeLockedStateStale:
                "This episode's unlock status changed. Please refresh."
            }
        case let .storage(error):
            switch error {
            case .diskFull:
                "Your device is low on storage."
            case .migrationFailed, .keychainUnavailable:
                nil
            }
        case .featureDisabled, .unexpected:
            nil
        }
    }
}
