import os

/// `os.Logger` tabanlı canlı log uygulaması (03 §10.3).
/// subsystem: `com.shortseries.app`, kategori = modül adı.
public struct OSLogger: Logging {
    public static let subsystem = "com.shortseries.app"

    private let logger: os.Logger

    /// - Parameter category: Modül adı (ör. "ContentKit", "PlayerKit", "App").
    public init(category: String) {
        logger = os.Logger(subsystem: Self.subsystem, category: category)
    }

    public func log(_ level: LogLevel, _ message: String) {
        // Mesajlar Logging sözleşmesi gereği PII içermez; bu yüzden .public işaretlenir.
        // PII taşıması gereken interpolasyonlar çağıran tarafta os.Logger'a doğrudan
        // `privacy: .private` ile yazılmalıdır.
        switch level {
        case .debug:
            #if DEBUG
                logger.debug("\(message, privacy: .public)")
            #endif
            return
        case .info:
            logger.info("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        }
    }
}
