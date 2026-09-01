import AppFoundation
import Foundation
import ShotCore

/// OCR metninden deterministik varlık çıkarımı.
///
/// Hem LLM'siz cihazların tek yolu, hem de LLM yolunun **tabanıdır**: model bir tarihi
/// atlarsa `NSDataDetector` yine bulur. İki kaynağın birleşimi `HeuristicAnalyzer` ve
/// `FoundationModelAnalyzer` içinde tekilleştirilir (04 §4.2).
public struct EntityExtractor: Sendable {
    public init() {}

    public func extract(from text: String) -> [ExtractedEntity] {
        guard !text.isEmpty else { return [] }
        var entities: [ExtractedEntity] = []
        entities.append(contentsOf: detectorEntities(in: text))
        entities.append(contentsOf: AmountParser.entities(in: text))
        entities.append(contentsOf: ibanEntities(in: text))
        entities.append(contentsOf: keyedEntities(in: text))
        return entities
    }

    // MARK: - NSDataDetector

    /// Sistem dedektörü: tarih, bağlantı, telefon, adres.
    ///
    /// Bunları elle regex ile yazmak yanlış olurdu — `NSDataDetector` tarih ayrıştırmayı
    /// yerelleştirilmiş biçimlerde ("12 Oca 2026", "Jan 12") zaten doğru yapar.
    private func detectorEntities(in text: String) -> [ExtractedEntity] {
        let types: NSTextCheckingResult.CheckingType = [.date, .link, .phoneNumber, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            Log.warning(.intelligence, "NSDataDetector kurulamadı")
            return []
        }

        let nsText = text as NSString
        let matches = detector.matches(
            in: text, options: [], range: NSRange(location: 0, length: nsText.length)
        )

        return matches.compactMap { match -> ExtractedEntity? in
            let raw = nsText.substring(with: match.range)

            switch match.resultType {
            case .date:
                guard let date = match.date else { return nil }
                return ExtractedEntity(
                    kind: .date,
                    rawValue: raw,
                    normalizedValue: ISO8601DateFormatter.shotSense.string(from: date),
                    confidence: 0.85
                )
            case .link:
                guard let url = match.url else { return nil }
                if url.scheme == "mailto" {
                    let address = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                    return ExtractedEntity(
                        kind: .email, rawValue: raw, normalizedValue: address, confidence: 0.9
                    )
                }
                return ExtractedEntity(
                    kind: .url, rawValue: raw, normalizedValue: url.absoluteString, confidence: 0.9
                )
            case .phoneNumber:
                guard let number = match.phoneNumber else { return nil }
                return ExtractedEntity(
                    kind: .phone,
                    rawValue: raw,
                    normalizedValue: number.filter { $0.isNumber || $0 == "+" },
                    confidence: 0.8
                )
            case .address:
                return ExtractedEntity(
                    kind: .address, rawValue: raw, normalizedValue: raw, confidence: 0.7
                )
            default:
                return nil
            }
        }
    }

    // MARK: - IBAN

    private static let ibanRegex = try? NSRegularExpression(
        pattern: "\\b[A-Z]{2}[0-9]{2}(?:[ ]?[A-Z0-9]{2,4}){2,8}\\b",
        options: []
    )

    private func ibanEntities(in text: String) -> [ExtractedEntity] {
        guard let regex = Self.ibanRegex else { return [] }
        let nsText = text as NSString

        return regex
            .matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            .compactMap { match in
                let raw = nsText.substring(with: match.range)
                let compact = raw.filter { $0.isLetter || $0.isNumber }.uppercased()
                // Checksum kapısı: desene uyan her dizi IBAN değildir (sipariş numaraları da uyar).
                guard ExtractionValidator.isValidIBAN(compact) else { return nil }
                return ExtractedEntity(
                    kind: .iban, rawValue: raw, normalizedValue: compact, confidence: 0.95
                )
            }
    }

    // MARK: - Anahtar sözcüğe dayalı varlıklar

    /// Bir değerin ne olduğunu **bağlamı** belirler: `4829` tek başına anlamsızdır, ama
    /// "Doğrulama kodu: 4829" satırında doğrulama kodudur. Bu yüzden bu varlıklar satır
    /// bazında, anahtar sözcük eşleşmesiyle çıkarılır.
    private struct KeyedRule {
        let kind: EntityKind
        let keywords: [String]
        let valuePattern: String
        let confidence: Double
    }

    private static let keyedRules: [KeyedRule] = [
        KeyedRule(
            kind: .wifiPassword,
            keywords: ["şifre", "sifre", "password", "parola", "pass"],
            valuePattern: "[A-Za-z0-9@#$%&*_\\-!.]{6,40}",
            confidence: 0.75
        ),
        KeyedRule(
            kind: .wifiSSID,
            keywords: ["wifi", "wi-fi", "ssid", "ağ adı", "network"],
            valuePattern: "[A-Za-z0-9 _\\-]{2,32}",
            confidence: 0.7
        ),
        KeyedRule(
            kind: .code,
            keywords: ["doğrulama", "dogrulama", "kod", "code", "otp", "pin", "kupon"],
            valuePattern: "[A-Z0-9]{4,12}",
            confidence: 0.75
        ),
        KeyedRule(
            kind: .trackingNumber,
            keywords: ["takip", "kargo", "tracking", "gönderi", "sipariş no", "barkod"],
            valuePattern: "[A-Z0-9]{8,25}",
            confidence: 0.75
        ),
        KeyedRule(
            kind: .flightNumber,
            keywords: ["uçuş", "ucus", "flight", "pnr", "sefer"],
            valuePattern: "[A-Z]{2}[ ]?[0-9]{3,4}",
            confidence: 0.8
        ),
    ]

    private func keyedEntities(in text: String) -> [ExtractedEntity] {
        var results: [ExtractedEntity] = []

        for line in text.components(separatedBy: .newlines) {
            let folded = TextNormalizer.fold(line)
            guard !folded.isEmpty else { continue }

            for rule in Self.keyedRules {
                guard rule.keywords.contains(where: { folded.contains(TextNormalizer.fold($0)) })
                else { continue }
                guard let value = firstMatch(of: rule.valuePattern, in: line, excluding: rule.keywords)
                else { continue }

                results.append(
                    ExtractedEntity(
                        kind: rule.kind,
                        rawValue: value,
                        normalizedValue: value,
                        confidence: rule.confidence
                    )
                )
            }
        }
        return results
    }

    /// Satırdaki ilk uygun değeri döndürür; anahtar sözcüğün kendisi değer sayılmaz
    /// ("Şifre: password123" satırında "password" değil "password123" alınmalı).
    private func firstMatch(
        of pattern: String,
        in line: String,
        excluding keywords: [String]
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        let foldedKeywords = keywords.map { TextNormalizer.fold($0) }

        // Değer yalnız bir etiket ayracından SONRA aranır ("Şifre: xyz", "SSID = xyz").
        // Ayraç yoksa satır bir etiket/başlıktır ("Wi-Fi Ağı"), değer taşımaz — böyle
        // satırlardan çıkarım yapmak "Wi" gibi anlamsız varlıklar üretir.
        let separatorRange = [":", "="]
            .map { nsLine.range(of: $0) }
            .filter { $0.location != NSNotFound }
            .min { $0.location < $1.location }
        guard let separatorRange else { return nil }

        let searchStart = separatorRange.location + separatorRange.length
        guard searchStart < nsLine.length else { return nil }
        let searchRange = NSRange(location: searchStart, length: nsLine.length - searchStart)

        for match in regex.matches(in: line, options: [], range: searchRange) {
            let candidate = nsLine.substring(with: match.range)
                .trimmingCharacters(in: .whitespaces)
            let foldedCandidate = TextNormalizer.fold(candidate)
            guard !candidate.isEmpty,
                  !foldedKeywords.contains(where: { foldedCandidate == $0 })
            else { continue }
            return candidate
        }
        return nil
    }
}
