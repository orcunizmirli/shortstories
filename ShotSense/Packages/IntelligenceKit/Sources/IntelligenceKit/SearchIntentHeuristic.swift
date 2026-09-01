import Foundation
import ShotCore

/// Doğal dil sorgusunu LLM olmadan yapılandırılmış niyete çevirir.
///
/// LLM'siz cihazlarda tek yol, LLM'li cihazlarda ise **kotayı korur**: Free katmanda aylık
/// 10 LLM ayrıştırması vardır (06 §3); "son 7 gün fişler" gibi kalıplaşmış sorgular kota
/// harcamadan burada çözülür.
public enum SearchIntentHeuristic {
    private static let categoryKeywords: [(keywords: [String], category: ShotCategory)] = [
        (["fiş", "fatura", "makbuz", "receipt", "invoice"], .receipt),
        (["bilet", "uçuş", "biniş", "ticket", "flight", "boarding"], .ticket),
        (["wifi", "wi-fi", "şifre", "parola", "password"], .wifi),
        (["sohbet", "mesaj", "konuşma", "chat", "message"], .conversation),
        (["tarif", "yemek", "recipe"], .recipe),
        (["makale", "haber", "yazı", "article", "news"], .article),
        (["kod", "hata", "terminal", "code", "error"], .code),
        (["ürün", "alışveriş", "product", "shopping"], .product),
        (["adres", "konum", "harita", "address", "location", "map"], .location),
        (["etkinlik", "toplantı", "randevu", "event", "meeting"], .event),
        (["iban", "banka", "hesap", "bank", "account"], .banking),
        (["kargo", "takip", "gönderi", "shipping", "tracking"], .shipping),
        (["kimlik", "pasaport", "ehliyet", "passport", "id"], .identity),
    ]

    private static let dateKeywords: [(keywords: [String], range: RelativeDateRange)] = [
        (["son 7 gün", "geçen hafta", "bu hafta", "last week", "last 7 days"], .last7Days),
        (["son 30 gün", "geçen ay", "bu ay", "last month", "last 30 days"], .last30Days),
        (["son 3 ay", "son 90 gün", "last 3 months", "last 90 days"], .last90Days),
        (["bu yıl", "this year"], .thisYear),
        (["geçen yıl", "last year"], .lastYear),
    ]

    public static func parse(_ query: String) -> SearchIntent {
        let folded = TextNormalizer.fold(query)
        guard !folded.isEmpty else { return .plain(query) }

        var consumed: [String] = []

        let category = categoryKeywords.first { entry in
            entry.keywords.contains { keyword in
                let foldedKeyword = TextNormalizer.fold(keyword)
                if folded.contains(foldedKeyword) {
                    consumed.append(foldedKeyword)
                    return true
                }
                return false
            }
        }?.category

        let dateRange = dateKeywords.first { entry in
            entry.keywords.contains { keyword in
                let foldedKeyword = TextNormalizer.fold(keyword)
                if folded.contains(foldedKeyword) {
                    consumed.append(foldedKeyword)
                    return true
                }
                return false
            }
        }?.range

        let bounds = amountBounds(in: query)

        // Yapılandırılmış olarak anlaşılan parçalar serbest metinden çıkarılır; aksi hâlde
        // "fiş" kelimesi hem filtre hem arama terimi olur ve sıralamayı bozar.
        var freeText = folded
        for phrase in consumed {
            freeText = freeText.replacingOccurrences(of: phrase, with: " ")
        }
        freeText = freeText
            .split(separator: " ")
            .filter { $0.count >= 2 }
            .joined(separator: " ")

        return SearchIntent(
            freeText: freeText.isEmpty ? "" : freeText,
            category: category,
            dateRange: dateRange,
            minAmount: bounds.minimum,
            maxAmount: bounds.maximum
        )
    }

    /// "500 tl üstü", "1000'den fazla", "under 50" gibi kalıplardan tutar sınırı çıkarır.
    static func amountBounds(in query: String) -> (minimum: Double?, maximum: Double?) {
        let folded = TextNormalizer.fold(query)
        guard let amount = AmountParser.matches(in: query).first?.amount
            ?? firstStandaloneNumber(in: query)
        else { return (nil, nil) }

        let lowerBoundMarkers = ["ustu", "uzeri", "fazla", "buyuk", "above", "over", "more than"]
        let upperBoundMarkers = ["alti", "altinda", "az", "kucuk", "under", "below", "less than"]

        if lowerBoundMarkers.contains(where: { folded.contains($0) }) { return (amount, nil) }
        if upperBoundMarkers.contains(where: { folded.contains($0) }) { return (nil, amount) }
        return (nil, nil)
    }

    private static func firstStandaloneNumber(in query: String) -> Double? {
        query
            .split { !$0.isNumber && $0 != "." && $0 != "," }
            .compactMap { AmountParser.normalize(String($0)) }
            .first
    }
}
