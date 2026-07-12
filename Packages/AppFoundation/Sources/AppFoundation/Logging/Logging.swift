/// Log seviyesi (03 §10.3): `debug` yalnız DEBUG build'de yazılır, `info` akış
/// kilometre taşları, `error` yakalanan AppError'lar (non-fatal), `fault` invariant ihlali.
public enum LogLevel: Int, Sendable, Equatable, Comparable, CaseIterable {
    case debug = 0
    case info
    case error
    case fault

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Loglama soyutlaması. Canlı uygulama `OSLogger`; Crashlytics breadcrumb köprüsü
/// AnalyticsKit üzerinden gelir (R6, F1).
///
/// PII KURALI (03 §10.3): mesaja e-posta, token, receipt YAZILMAZ; kullanıcı yalnız
/// opak `userID` ile anılır. Bu sözleşme tüm `Logging` uygulamaları için bağlayıcıdır.
public protocol Logging: Sendable {
    func log(_ level: LogLevel, _ message: String)
}

public extension Logging {
    func debug(_ message: String) {
        log(.debug, message)
    }

    func info(_ message: String) {
        log(.info, message)
    }

    func error(_ message: String) {
        log(.error, message)
    }

    func fault(_ message: String) {
        log(.fault, message)
    }
}
