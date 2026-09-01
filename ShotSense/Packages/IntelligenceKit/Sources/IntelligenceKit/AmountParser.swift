import Foundation
import ShotCore

/// Metinde geçen para tutarlarını bulur ve yerelden bağımsız ondalık sayıya çevirir.
///
/// **Neden elle yazıldı:** `NumberFormatter` tek bir yerel varsayar. Ekran görüntüleri
/// karışıktır — Türk kullanıcının ekranında `1.234,56 TL` de `$1,234.56` da bulunur.
/// Ayraç kararı biçimden çıkarılmalıdır, kullanıcının yerelinden değil.
public enum AmountParser {
    /// Tanınan para birimi işaretleri ve ISO-4217 karşılıkları.
    static let currencyMarkers: [String: String] = [
        "₺": "TRY", "TL": "TRY", "TRY": "TRY",
        "$": "USD", "USD": "USD",
        "€": "EUR", "EUR": "EUR",
        "£": "GBP", "GBP": "GBP",
        "CHF": "CHF", "SEK": "SEK", "NOK": "NOK", "DKK": "DKK",
        "PLN": "PLN", "RUB": "RUB", "AED": "AED", "SAR": "SAR",
    ]

    public struct Match: Sendable, Hashable {
        /// Metinde geçtiği hâli (grounding bunu arar).
        public let rawValue: String
        public let amount: Double
        public let currencyCode: String?
    }

    private static let numberPattern = "[0-9]{1,3}(?:[.,\\s][0-9]{3})*(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?"

    private static let regex: NSRegularExpression? = {
        let markers = currencyMarkers.keys
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        // İşaret sayıdan önce (₺249,90) veya sonra (249,90 TL) gelebilir; ikisi de yakalanır.
        let pattern = "(?:(\(markers))\\s*(\(numberPattern)))|(?:(\(numberPattern))\\s*(\(markers)))"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    public static func matches(in text: String) -> [Match] {
        guard let regex else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        var results: [Match] = []
        for match in regex.matches(in: text, options: [], range: range) {
            // Grup 1/2 = işaret önce, grup 3/4 = işaret sonra.
            let markerRange = match.range(at: 1).location != NSNotFound
                ? match.range(at: 1) : match.range(at: 4)
            let numberRange = match.range(at: 2).location != NSNotFound
                ? match.range(at: 2) : match.range(at: 3)
            guard numberRange.location != NSNotFound else { continue }

            let numberText = nsText.substring(with: numberRange)
            guard let amount = normalize(numberText) else { continue }

            let currency: String? = markerRange.location != NSNotFound
                ? currencyMarkers[nsText.substring(with: markerRange).uppercased()]
                : nil

            results.append(
                Match(rawValue: numberText, amount: amount, currencyCode: currency)
            )
        }
        return results
    }

    /// Ayraç biçiminden ondalık değeri çıkarır.
    ///
    /// Kural: **en sağdaki ayraç** ondalık ayracıdır — ama yalnız ardından 1–2 hane geliyorsa.
    /// `1.234` binlik, `1.23` ondalıktır; `1.234,56` içinde virgül ondalıktır.
    public static func normalize(_ value: String) -> Double? {
        let compact = value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !compact.isEmpty, compact.contains(where: \.isNumber) else { return nil }

        let lastSeparatorIndex = compact.lastIndex { $0 == "." || $0 == "," }
        guard let lastSeparatorIndex else { return Double(compact) }

        let decimalsCount = compact.distance(from: compact.index(after: lastSeparatorIndex),
                                             to: compact.endIndex)
        if decimalsCount == 1 || decimalsCount == 2 {
            let integerPart = compact[compact.startIndex ..< lastSeparatorIndex]
                .filter { $0.isNumber }
            let fractionPart = compact[compact.index(after: lastSeparatorIndex)...]
                .filter { $0.isNumber }
            return Double(integerPart + "." + fractionPart)
        }
        // Tüm ayraçlar binliktir.
        return Double(compact.filter(\.isNumber))
    }

    /// Bulunan tutarları domain varlığına çevirir.
    ///
    /// Desen **para birimi işareti zorunlu** tutar: ekran görüntülerinde işaretsiz sayılar
    /// çoğunlukla sipariş numarası, saat veya beğeni sayısıdır. İşaretsiz sayıyı tutar saymak
    /// yanlış-pozitifi kabul edilemez düzeye çıkarır, bu yüzden bilinçli olarak kaçırılır.
    public static func entities(in text: String) -> [ExtractedEntity] {
        matches(in: text).map { match in
            ExtractedEntity(
                kind: .amount,
                rawValue: match.rawValue,
                normalizedValue: String(format: "%.2f", match.amount),
                currencyCode: match.currencyCode,
                confidence: 0.9
            )
        }
    }
}
