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
        case .network(let error):
            switch error {
            case .offline, .timeout:
                return true
            case .server(let status):
                return status >= 500 || status == 429
            case .decoding:
                return false
            }
        case .playback(let error):
            return error == .signedURLExpired
        case .auth, .wallet, .content, .storage, .featureDisabled, .unexpected:
            return false
        }
    }

    /// Kullanıcıya gösterilebilir mesaj; kullanıcıya hiç gösterilmeyen arka plan
    /// hataları için `nil` (gösterim stratejisi: 03 §10.2).
    var userFacingMessage: LocalizedStringResource? {
        switch self {
        case .network(let error):
            switch error {
            case .offline:
                return "You're offline. Check your connection and try again."
            case .timeout:
                return "The connection timed out. Please try again."
            case .server:
                return "Something went wrong on our side. Please try again."
            case .decoding:
                return "Something went wrong. Please try again."
            }
        case .auth(let error):
            switch error {
            case .sessionExpired:
                return "Your session has expired. Please try again."
            case .linkingFailed:
                return "We couldn't link your account. Please try again."
            case .guestBootstrapFailed:
                return "We couldn't set up your account. Check your connection and try again."
            }
        case .playback(let error):
            switch error {
            case .assetUnavailable:
                return "This episode can't be played right now."
            case .drmDenied:
                return "This content can't be played on this device."
            case .signedURLExpired:
                return nil // player katmanı URL'i sessizce tazeler
            }
        case .wallet(let error):
            switch error {
            case .insufficientCoins:
                // "Hata" değil akıştır: CoinMagazasi'na yönlendirir (03 §10.2)
                return "You don't have enough coins."
            case .purchaseFailed(let status):
                switch status {
                case .userCancelled:
                    return nil
                case .pending:
                    return "Your purchase is still processing. Your coins will arrive shortly."
                case .verificationFailed, .unknown:
                    return "The purchase couldn't be completed. Please try again."
                }
            case .receiptValidationFailed:
                return "We're verifying your purchase. Your coins will be added shortly."
            case .transactionConflict:
                return "This transaction was already processed."
            }
        case .content(let error):
            switch error {
            case .notFound:
                return "This content is no longer available."
            case .regionBlocked:
                return "This content isn't available in your region."
            case .episodeLockedStateStale:
                return "This episode's unlock status changed. Please refresh."
            }
        case .storage(let error):
            switch error {
            case .diskFull:
                return "Your device is low on storage."
            case .migrationFailed, .keychainUnavailable:
                return nil
            }
        case .featureDisabled, .unexpected:
            return nil
        }
    }
}
