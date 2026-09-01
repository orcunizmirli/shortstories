import Foundation

/// Katmanlar arasında taşınan, kullanıcıya gösterilebilir hata tipi.
///
/// Adaptörler kendi çerçeve hatalarını (Vision, Photos, StoreKit) bu tipe çevirir; UI katmanı
/// yalnızca `AppError` görür. Böylece `LibraryKit` hiçbir Apple servis çerçevesini import etmez (R3).
public struct AppError: Error, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// Kullanıcı izin vermedi veya izin geri alındı.
        case permissionDenied
        /// Kaynak (asset, kayıt) artık yok.
        case notFound
        /// Cihaz bu yeteneği desteklemiyor (ör. Apple Intelligence kapalı).
        case unsupportedDevice
        /// Geçici hata; yeniden denenebilir.
        case transient
        /// Girdi geçersiz veya bozuk.
        case invalidInput
        /// Kota/yetki sınırı (Free katman limiti).
        case quotaExceeded
        /// Sınıflandırılamayan hata.
        case unknown
    }

    public let kind: Kind
    /// Geliştiriciye yönelik, **hassas veri içermeyen** kısa açıklama.
    public let debugMessage: String
    /// Sarmalanan alt hata (log için; kullanıcıya gösterilmez).
    public let underlying: String?

    public init(_ kind: Kind, _ debugMessage: String, underlying: (any Error)? = nil) {
        self.kind = kind
        self.debugMessage = debugMessage
        self.underlying = underlying.map { String(describing: $0) }
    }

    /// Yeniden denemenin anlamlı olup olmadığı — `AnalysisPipeline` geri çekilme kararında kullanır.
    public var isRetryable: Bool {
        kind == .transient
    }
}
