import Foundation
import os

/// Uygulama genelinde tek log giriş noktası.
///
/// KANON §7: ham ekran görüntüsü metni, şifre, IBAN veya kod **hiçbir zaman** loglanmaz.
/// Bu yüzden `Log` yalnızca sabit (interpolasyonsuz) mesajlar ve `Redaction` ile
/// maskelenmiş değerler kabul eder — çağıran taraf yanlışlıkla hassas veri geçiremesin diye
/// API'de `String` interpolasyonu yerine ayrık `detail` parametresi kullanılır.
public enum Log {
    private static let subsystem = "com.shotsense.app"

    public enum Category: String, Sendable, CaseIterable {
        case ingest
        case ocr
        case intelligence
        case index
        case search
        case action
        case paywall
        case ui
        case lifecycle
    }

    private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Rutin akış bilgisi. Yalnız hata ayıklama derlemelerinde kalıcıdır.
    public static func debug(_ category: Category, _ message: String, detail: String? = nil) {
        logger(category).debug("\(message, privacy: .public) \(detail ?? "", privacy: .private)")
    }

    /// Kalıcı olarak ilgi çeken olaylar (pipeline başladı/bitti, izin değişti).
    public static func info(_ category: Category, _ message: String, detail: String? = nil) {
        logger(category).info("\(message, privacy: .public) \(detail ?? "", privacy: .private)")
    }

    /// Beklenen ama istenmeyen durumlar (fallback'e düşüldü, yeniden deneniyor).
    public static func warning(_ category: Category, _ message: String, detail: String? = nil) {
        logger(category).warning("\(message, privacy: .public) \(detail ?? "", privacy: .private)")
    }

    /// Kullanıcıya yansıyan veya veri kaybına yol açabilecek hatalar.
    public static func error(_ category: Category, _ message: String, error: (any Error)? = nil) {
        let description = error.map { String(describing: type(of: $0)) + ": " + $0.localizedDescription } ?? ""
        logger(category).error("\(message, privacy: .public) \(description, privacy: .private)")
    }
}
