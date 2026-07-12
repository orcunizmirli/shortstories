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
    case insufficientCoins
    case purchaseFailed(StoreKitStatus)
    case receiptValidationFailed
    case transactionConflict
}

public enum ContentError: Sendable, Equatable {
    case notFound
    case regionBlocked
    case episodeLockedStateStale
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
