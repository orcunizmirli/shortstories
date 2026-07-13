import Foundation

/// Wire JSON kodlamasının TEK kaynaklı konfigürasyonu (05 §1 kural 7-8): anahtarlar camelCase
/// aynen taşınır (`useDefaultKeys`), tarihler ISO 8601 / RFC 3339 UTC'dir ve
/// `ISO8601DateFormatter` (fractional seconds destekli) ile okunur — "2026-07-11T09:31:02.123Z"
/// ve "2026-07-11T09:31:02Z" biçimlerinin İKİSİ de kabul edilir. `JSONDecoder`'ın hazır
/// `.iso8601` stratejisi fractional saniyeyi REDDETTİĞİ için custom strateji zorunludur.
/// Canlı `APIClient` ve `MockAPIClient` (TestSupport) aynı konfigürasyonu buradan alır.
public extension JSONDecoder {
    static func shortSeriesDefault() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601DateParser.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "ISO 8601 olmayan tarih: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

public extension JSONEncoder {
    static func shortSeriesDefault() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Formatter'lar allocation maliyeti nedeniyle statik önbelleklidir. `ISO8601DateFormatter`
/// yapılandırması kurulumdan sonra değişmediği için okuma-yalnız kullanımda thread-safe'tir;
/// `nonisolated(unsafe)` bu nedenle güvenlidir.
enum ISO8601DateParser {
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Önce fractional saniyeli biçim denenir, sonra saniye hassasiyetli biçim.
    static func date(from raw: String) -> Date? {
        fractional.date(from: raw) ?? standard.date(from: raw)
    }
}
