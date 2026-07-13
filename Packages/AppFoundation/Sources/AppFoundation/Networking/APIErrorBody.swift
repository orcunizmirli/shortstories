import Foundation

/// Tüm 4xx/5xx yanıtlarının ortak hata zarfı (05 §10.1 şemasının birebir karşılığı).
/// `error.code` → tipli `AppError` eşlemesi YALNIZ AppFoundation API katmanında yapılır
/// (05 §10.3 sınır kuralı); feature modülleri bu gövdeyi asla görmez.
public struct APIErrorBody: Decodable, Sendable {
    public struct Payload: Decodable, Sendable {
        /// SCREAMING_SNAKE, makine-okur, sözleşmenin parçası (ör. `EPISODE_LOCKED`).
        public let code: String
        /// Lokalize, doğrudan gösterilebilir mesaj.
        public let message: String
        /// Koda özgü ek alanlar (opsiyonel; ör. `unlockPrice`, `shortfall`).
        public let details: JSONValue?
        /// İstemcinin otomatik retry ipucu.
        public let retryable: Bool?
    }

    public let error: Payload
    public let requestId: String?
}

/// Hafif dinamik JSON sarmalayıcı (05 §10.1): `details` gibi koda özgü serbest-şema
/// alanları tip kaybetmeden taşır.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON değeri bilinen hiçbir tipe uymuyor"
            )
        }
    }
}
