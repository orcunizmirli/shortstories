import Foundation

/// Model çıktısını kullanıcıya göstermeden önce kaynak metne karşı doğrulayan kapı.
///
/// **Neden domain'de:** kural tamamen saf metin işidir; `ShotCore` içinde durunca simülatörsüz
/// birim testleriyle kapsanabilir ve hem LLM hem heuristik yol aynı kapıdan geçer (04 §5).
///
/// Kural (KANON §6): değeri kaynak OCR metninde bulunamayan varlık **atılır**. Model bir tutar
/// veya tarih uydurduğunda bu kapıya takılır ve arayüze hiç ulaşmaz.
public struct ExtractionValidator: Sendable {
    /// ISO-4217'nin ekran görüntülerinde gerçekçi olarak görülen alt kümesi.
    /// Liste kapalıdır: modelin uydurduğu "TRY2", "USDT" gibi kodlar elenir.
    public static let supportedCurrencyCodes: Set<String> = [
        "TRY", "USD", "EUR", "GBP", "CHF", "JPY", "CNY", "RUB", "AED",
        "SAR", "CAD", "AUD", "SEK", "NOK", "DKK", "PLN", "CZK", "BGN", "RON"
    ]

    public init() {}

    /// Varlık listesini doğrular: geçersizler atılır, geçerliler `isGrounded = true` ile döner.
    public func validate(_ entities: [ExtractedEntity], against sourceText: String) -> [ExtractedEntity] {
        let foldedSource = TextNormalizer.fold(sourceText)
        let alphanumericSource = TextNormalizer.alphanumeric(sourceText)
        let digitSource = TextNormalizer.digits(sourceText)

        var seen = Set<String>()
        var result: [ExtractedEntity] = []

        for entity in entities {
            guard isStructurallyValid(entity) else { continue }
            guard isGrounded(
                entity,
                foldedSource: foldedSource,
                alphanumericSource: alphanumericSource,
                digitSource: digitSource
            ) else { continue }

            // Aynı tür + aynı normalize değer birden çok kez gelirse (model tekrarlar) tek tutulur.
            let key = entity.kind.rawValue + "|" + TextNormalizer.fold(entity.normalizedValue)
            guard seen.insert(key).inserted else { continue }

            result.append(entity.grounded(true))
        }
        return result
    }

    // MARK: - Yapısal doğrulama

    /// Değerin kendi türünün kurallarına uyup uymadığı (kaynak metinden bağımsız).
    public func isStructurallyValid(_ entity: ExtractedEntity) -> Bool {
        let value = entity.normalizedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !entity.rawValue.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }

        switch entity.kind {
        case .date:
            return entity.dateValue != nil
        case .amount:
            guard let amount = entity.amountValue, amount.isFinite, amount >= 0 else { return false }
            guard let code = entity.currencyCode else { return true }
            return Self.supportedCurrencyCodes.contains(code)
        case .iban:
            return Self.isValidIBAN(value)
        case .email:
            return Self.isPlausibleEmail(value)
        case .url:
            return URL(string: value)?.scheme != nil
        case .phone:
            let digits = TextNormalizer.digits(value)
            return digits.count >= 7 && digits.count <= 15
        case .merchant, .person, .address, .wifiSSID, .wifiPassword,
             .code, .trackingNumber, .flightNumber:
            return value.count >= 2 && value.count <= 120
        }
    }

    // MARK: - Kaynak temellendirme

    private func isGrounded(
        _ entity: ExtractedEntity,
        foldedSource: String,
        alphanumericSource: String,
        digitSource: String
    ) -> Bool {
        switch entity.kind {
        case .date:
            // Tarih normalize edilirken biçim tamamen değişir ("12 Oca 2026" → "2026-01-12"),
            // bu yüzden kaynakta ARANACAK olan ham hâlidir.
            return foldedSource.contains(TextNormalizer.fold(entity.rawValue))
        case .amount:
            // Ayraçlar ülkeye göre değişir (1.234,56 / 1,234.56); yalnız rakam dizisi karşılaştırılır.
            let digits = TextNormalizer.digits(entity.rawValue)
            guard !digits.isEmpty else { return false }
            return digitSource.contains(digits)
        case .iban, .phone, .trackingNumber, .flightNumber, .code:
            // Boşluk/tire ile parçalanmış olabilir.
            let compact = TextNormalizer.alphanumeric(entity.rawValue)
            guard compact.count >= 4 else { return false }
            return alphanumericSource.contains(compact)
        case .merchant, .person, .address, .url, .email, .wifiSSID, .wifiPassword:
            let folded = TextNormalizer.fold(entity.rawValue)
            guard folded.count >= 2 else { return false }
            return foldedSource.contains(folded)
        }
    }

    // MARK: - Biçim yardımcıları

    /// IBAN mod-97 checksum doğrulaması (ISO 13616).
    ///
    /// Bu kontrol olmadan model "TR" ile başlayan herhangi bir rakam dizisini IBAN sanabilir;
    /// kullanıcı da yanlış hesaba para gönderebilir. Bu yüzden checksum **zorunludur**.
    public static func isValidIBAN(_ value: String) -> Bool {
        let compact = value.uppercased().filter { $0.isLetter || $0.isNumber }
        guard compact.count >= 15, compact.count <= 34 else { return false }
        guard compact.prefix(2).allSatisfy(\.isLetter), compact.dropFirst(2).prefix(2).allSatisfy(\.isNumber)
        else { return false }

        // İlk 4 karakter sona taşınır, harfler A=10 … Z=35 ile sayıya çevrilir, mod 97 == 1 olmalı.
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            let chunk: String
            if let digit = character.wholeNumberValue, character.isNumber {
                chunk = String(digit)
            } else if let ascii = character.asciiValue, character.isLetter {
                chunk = String(Int(ascii) - 55)
            } else {
                return false
            }
            for digitCharacter in chunk {
                guard let digit = digitCharacter.wholeNumberValue else { return false }
                remainder = (remainder * 10 + digit) % 97
            }
        }
        return remainder == 1
    }

    /// Basit ama yanlış-pozitifi düşük e-posta kontrolü.
    public static func isPlausibleEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return !value.contains(" ")
    }
}
