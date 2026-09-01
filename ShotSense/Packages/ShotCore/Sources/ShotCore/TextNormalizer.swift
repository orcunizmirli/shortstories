import Foundation

/// Metin karşılaştırmalarının tek noktası: grounding doğrulaması, arama tokenizasyonu ve
/// yinelenen tespiti aynı normalizasyonu kullanmalıdır, aksi hâlde "bulundu/bulunamadı"
/// kararları katmanlar arasında tutarsızlaşır.
public enum TextNormalizer {
    /// Aksan ve büyük/küçük harf duyarsız karşılaştırma biçimi.
    ///
    /// Türkçe `I/ı/İ/i` çiftleri `Locale` verilmeden yanlış katlanır; bu yüzden katlama
    /// açıkça Türkçe yerelinde yapılır ve sonuç ayrıca `precomposedStringWithCanonicalMapping`
    /// ile normalize edilir (OCR bazen ayrık birleştirici işaret üretir).
    public static func fold(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "tr_TR")
            )
    }

    /// Yalnızca harf ve rakamları bırakır — biçimlendirme farklarını (boşluk, nokta, tire)
    /// yok sayarak sayısal/kimlik değerlerini karşılaştırmak için.
    ///
    /// Örn. `TR33 0006 1005 1978 6457 8413 26` ile `TR330006100519786457841326` eşleşir.
    public static func alphanumeric(_ value: String) -> String {
        fold(value).filter { $0.isLetter || $0.isNumber }
    }

    /// Yalnızca rakamları bırakır — tutar ve telefon karşılaştırması için.
    public static func digits(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    /// Arama ve BM25 için token listesi. Harf/rakam dizileri; 2 karakterden kısa olanlar atılır.
    public static func tokenize(_ value: String) -> [String] {
        fold(value)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { $0.count >= 2 }
    }
}
