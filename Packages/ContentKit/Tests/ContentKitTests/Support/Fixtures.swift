import Foundation

/// Contract fixture yükleyici (05 §12 kural 6): fixture'lar wire alan adlarını taşır ve
/// decode sınırını sınar. Decoder, AppFoundation `APIClient`/`MockAPIClient` ile birebir
/// aynı konfigürasyondadır (.useDefaultKeys — 05 kural 7).
enum Fixtures {
    /// Tarih stratejisi: RFC 3339 / ISO 8601, fractional-seconds'lı ("…T09:31:02.123Z")
    /// ve saniye hassasiyetli iki biçim de kabul edilir.
    ///
    /// TODO(SS-020 paraleli): AppFoundation üretim decoder'ı tek kaynaklı yardımcıya
    /// (`JSONDecoder.shortSeriesDefault` benzeri) taşındığında bu test decoder'ı ONU
    /// kullanmalı; o güne dek aynı `.custom` strateji burada yerel kurulur.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseISO8601(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Geçersiz ISO 8601 tarihi: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    /// İki RFC 3339 biçimini de dener: önce saniye hassasiyeti, sonra fractional-seconds.
    static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try decoder.decode(type, from: data(name))
    }

    enum FixtureError: Error {
        case notFound(String)
    }
}

/// Testlerde sabit tarih üretimi (fixture'larla aynı biçim: RFC 3339 / UTC;
/// fractional-seconds da desteklenir).
func isoDate(_ string: String) -> Date {
    guard let date = Fixtures.parseISO8601(string) else {
        fatalError("Geçersiz test tarihi: \(string)")
    }
    return date
}
