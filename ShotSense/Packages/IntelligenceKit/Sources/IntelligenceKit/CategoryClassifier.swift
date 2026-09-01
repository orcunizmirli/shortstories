import Foundation
import ShotCore

/// Anahtar sözcük ağırlıklarına dayalı deterministik sınıflandırıcı.
///
/// LLM'siz cihazlarda tek sınıflandırma yolu, LLM'li cihazlarda ise **doğrulama sinyalidir**:
/// model ile heuristik aynı kategoride buluşuyorsa güven yükseltilir (04 §4.2).
///
/// Sözlük Türkçe ve İngilizce içerir; ağırlıklar "bu kelime tek başına ne kadar ayırt edici"
/// sorusuna göre verilmiştir — `toplam` her fişte geçer ama ürün sayfalarında da geçer (2),
/// `kdv` neredeyse yalnız fişlerde geçer (5).
public struct CategoryClassifier: Sendable {
    private struct Signal {
        let keywords: [String: Int]
        let patterns: [(pattern: String, weight: Int)]
    }

    public init() {}

    /// Bir kategorinin kazanması için gereken en düşük ham puan.
    /// Altında kalan her şey `.other` olur — yanlış sınıflandırmaktansa sınıflandırmamak yeğdir.
    private static let minimumScore = 4

    private static let signals: [ShotCategory: Signal] = [
        .receipt: Signal(
            keywords: [
                "kdv": 5, "fiş": 5, "fatura": 4, "toplam": 2, "ara toplam": 4, "tutar": 2,
                "ödendi": 3, "nakit": 3, "kredi kartı": 3, "vergi": 3, "makbuz": 5,
                "receipt": 5, "invoice": 4, "subtotal": 4, "total": 2, "tax": 3, "vat": 4,
                "paid": 3, "cash": 2, "change": 2,
            ],
            patterns: []
        ),
        .ticket: Signal(
            keywords: [
                "bilet": 5, "koltuk": 4, "sefer": 3, "kalkış": 4, "varış": 4, "peron": 4,
                "biniş": 5, "rezervasyon": 3, "pnr": 5, "yolcu": 3,
                "ticket": 5, "seat": 4, "boarding": 5, "gate": 4, "departure": 4,
                "arrival": 4, "passenger": 3, "booking": 3,
            ],
            patterns: [("\\b[A-Z]{2}[ ]?[0-9]{3,4}\\b", 3)]
        ),
        .wifi: Signal(
            keywords: [
                "wifi": 5, "wi-fi": 5, "ssid": 5, "ağ adı": 4, "şifre": 2, "parola": 2,
                "network name": 4, "password": 2, "hotspot": 4,
            ],
            patterns: []
        ),
        .conversation: Signal(
            keywords: [
                "yazıyor": 3, "çevrimiçi": 3, "son görülme": 5, "mesaj": 2, "sohbet": 4,
                "typing": 3, "online": 2, "last seen": 5, "message": 2, "delivered": 3,
                "read": 1, "reply": 2,
            ],
            patterns: []
        ),
        .recipe: Signal(
            keywords: [
                "malzeme": 5, "tarif": 5, "yemek": 2, "pişirme": 4, "porsiyon": 4,
                "fırın": 3, "kaşık": 3, "bardak": 2, "hazırlanışı": 5,
                "ingredients": 5, "recipe": 5, "servings": 4, "preheat": 4,
                "tablespoon": 4, "teaspoon": 4, "bake": 3,
            ],
            patterns: []
        ),
        .code: Signal(
            keywords: [
                "func": 3, "class": 2, "import": 3, "return": 2, "error": 2, "exception": 4,
                "null": 3, "undefined": 4, "stack trace": 5, "terminal": 3, "git": 3,
                "npm": 4, "swift": 2, "python": 3, "traceback": 5,
            ],
            patterns: [("[{};]\\s*$", 2), ("^\\s{4,}\\S", 1)]
        ),
        .product: Signal(
            keywords: [
                "sepete": 5, "satın al": 4, "indirim": 4, "kargo bedava": 4, "stokta": 4,
                "yorum": 2, "puan": 2, "beden": 3, "renk": 2,
                "add to cart": 5, "buy now": 4, "discount": 3, "in stock": 4,
                "reviews": 3, "rating": 2, "free shipping": 4,
            ],
            patterns: []
        ),
        .location: Signal(
            keywords: [
                "yol tarifi": 5, "konum": 4, "adres": 4, "mahalle": 3, "cadde": 3, "sokak": 3,
                "km": 2, "dakika": 1, "harita": 4,
                "directions": 5, "route": 4, "address": 4, "street": 3, "avenue": 3,
                "map": 3, "nearby": 3,
            ],
            patterns: []
        ),
        .event: Signal(
            keywords: [
                "etkinlik": 5, "davet": 4, "takvim": 4, "toplantı": 5, "randevu": 5,
                "saat": 1, "tarih": 2, "katılımcı": 4,
                "event": 4, "invite": 4, "calendar": 4, "meeting": 5, "appointment": 5,
                "rsvp": 5, "attendees": 4,
            ],
            patterns: []
        ),
        .banking: Signal(
            keywords: [
                "iban": 5, "hesap": 3, "bakiye": 5, "havale": 5, "eft": 5, "transfer": 3,
                "banka": 4, "kart no": 4, "ekstre": 5, "borç": 3,
                "balance": 4, "account": 2, "wire": 3, "statement": 4, "routing": 4,
            ],
            patterns: [("\\b[A-Z]{2}[0-9]{2}[ ]?[A-Z0-9]{4}", 4)]
        ),
        .shipping: Signal(
            keywords: [
                "kargo": 5, "takip no": 5, "gönderi": 4, "teslimat": 5, "dağıtımda": 5,
                "teslim edildi": 5, "sipariş durumu": 4,
                "shipping": 4, "tracking": 5, "delivered": 4, "out for delivery": 5,
                "shipment": 4, "courier": 4,
            ],
            patterns: []
        ),
        .identity: Signal(
            keywords: [
                "kimlik": 5, "tc no": 5, "pasaport": 5, "ehliyet": 5, "doğum tarihi": 4,
                "seri no": 3, "üyelik": 3,
                "passport": 5, "driver license": 5, "id number": 4, "date of birth": 4,
                "membership": 3,
            ],
            patterns: []
        ),
        .article: Signal(
            keywords: [
                "dakika okuma": 5, "yazar": 3, "kaynak": 2, "yayınlandı": 4, "haber": 3,
                "min read": 5, "author": 3, "published": 4, "share": 1, "comments": 2,
            ],
            patterns: []
        ),
    ]

    /// Metni sınıflandırır.
    /// - Returns: Kategori ve `0...1` aralığında güven. Hiçbir sinyal eşiği aşmazsa `.other`, 0.
    public func classify(_ text: String) -> (category: ShotCategory, confidence: Double) {
        let folded = TextNormalizer.fold(text)
        guard !folded.isEmpty else { return (.other, 0) }

        var scores: [ShotCategory: Int] = [:]

        for (category, signal) in Self.signals {
            var score = 0
            for (keyword, weight) in signal.keywords where folded.contains(TextNormalizer.fold(keyword)) {
                score += weight
            }
            for entry in signal.patterns where matches(entry.pattern, in: text) {
                score += entry.weight
            }
            if score > 0 { scores[category] = score }
        }

        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= Self.minimumScore
        else {
            return (.other, 0)
        }

        // Güven, kazananın toplam kanıt içindeki payıdır: iki kategori yakın puan aldıysa
        // (ör. fiş vs ürün) güven düşer ve pipeline LLM sonucunu tercih eder.
        let total = scores.values.reduce(0, +)
        let share = Double(best.value) / Double(total)
        // Mutlak kanıt miktarı da güveni etkiler: 5 puanla kazanmak 40 puanla kazanmak değildir.
        let magnitude = min(Double(best.value) / 20.0, 1.0)
        return (best.key, min(0.5 * share + 0.5 * magnitude, 0.95))
    }

    private func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.anchorsMatchLines]
        ) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
