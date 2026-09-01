import Foundation

/// Ekran görüntüsünden çıkarılan tek bir yapılandırılmış bilgi parçası.
public enum EntityKind: String, Sendable, Codable, CaseIterable, Hashable {
    case date
    case amount
    case merchant
    case url
    case phone
    case email
    case iban
    case trackingNumber
    case flightNumber
    case address
    case wifiSSID
    case wifiPassword
    /// Doğrulama kodu, kupon kodu, PIN.
    case code
    case person

    /// Varsayılan olarak maskelenmesi gereken türler (KANON §7).
    public var isSensitive: Bool {
        switch self {
        case .iban, .wifiPassword, .code:
            return true
        case .date, .amount, .merchant, .url, .phone, .email,
             .trackingNumber, .flightNumber, .address, .wifiSSID, .person:
            return false
        }
    }

    /// Bu türün bir aksiyona (hatırlatıcı, takvim, arama) çevrilebilir olup olmadığı.
    public var isActionable: Bool {
        switch self {
        case .date, .url, .phone, .email, .address, .trackingNumber, .flightNumber:
            return true
        case .amount, .merchant, .iban, .wifiSSID, .wifiPassword, .code, .person:
            return false
        }
    }
}

public struct ExtractedEntity: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let kind: EntityKind
    /// Değerin OCR metninde geçtiği hâli — grounding doğrulaması buna bakar.
    public let rawValue: String
    /// Makine tarafından kullanılabilir hâl: ISO-8601 tarih, ondalık tutar, E.164 telefon.
    public let normalizedValue: String
    /// ISO-4217 kodu; yalnız `.amount` için doludur.
    public let currencyCode: String?
    public let confidence: Double
    /// `ExtractionValidator` değeri kaynak metinde bulabildi mi.
    ///
    /// `false` olan varlıklar **kullanıcıya gösterilmez** (04 §5). Kayıtta tutulmalarının
    /// sebebi kalite ölçümüdür: halüsinasyon oranı bu alandan hesaplanır.
    public let isGrounded: Bool

    public init(
        id: UUID = UUID(),
        kind: EntityKind,
        rawValue: String,
        normalizedValue: String,
        currencyCode: String? = nil,
        confidence: Double = 1.0,
        isGrounded: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.rawValue = rawValue
        self.normalizedValue = normalizedValue
        self.currencyCode = currencyCode
        self.confidence = min(max(confidence, 0), 1)
        self.isGrounded = isGrounded
    }

    /// Doğrulama sonucunu uygulayarak kopya üretir.
    public func grounded(_ value: Bool) -> ExtractedEntity {
        ExtractedEntity(
            id: id,
            kind: kind,
            rawValue: rawValue,
            normalizedValue: normalizedValue,
            currencyCode: currencyCode,
            confidence: confidence,
            isGrounded: value
        )
    }

    /// Tarih türü varlığın çözümlenmiş `Date` karşılığı.
    ///
    /// Ekran görüntülerinde saat bilgisi çoğu zaman yoktur, bu yüzden normalize edilmiş değer
    /// hem tam tarih-saat hem de yalnız-tarih biçiminde gelebilir; ikisi de kabul edilir.
    public var dateValue: Date? {
        guard kind == .date else { return nil }
        return ISO8601DateFormatter.shotSense.date(from: normalizedValue)
            ?? ISO8601DateFormatter.shotSenseDateOnly.date(from: normalizedValue)
    }

    /// Tutar türü varlığın sayısal karşılığı.
    public var amountValue: Double? {
        guard kind == .amount else { return nil }
        return Double(normalizedValue)
    }
}

extension ISO8601DateFormatter {
    /// Varlık normalizasyonunda kullanılan tek biçimlendirici.
    ///
    /// Ekran görüntülerinde saat bilgisi çoğu zaman yoktur; bu yüzden tam tarih-saat ve
    /// yalnız-tarih biçimlerinin ikisi de kabul edilir.
    public static let shotSense: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static let shotSenseDateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
