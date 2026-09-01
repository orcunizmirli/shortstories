import Foundation

/// OCR davranışını belirleyen ayarlar.
public struct OCRConfiguration: Sendable, Hashable {
    /// BCP-47 dil kodları, öncelik sırasıyla. Boş bırakılırsa Vision dili kendi seçer.
    public let languages: [String]
    /// Bu eşiğin altındaki tanıma sonuçları atılır.
    ///
    /// Ekran görüntüleri yüksek kontrastlı ve dijital kökenlidir; gerçek dünya fotoğraflarına
    /// göre çok daha temiz tanınır. Bu yüzden eşik alışıldık `0.3` yerine yüksek tutulur:
    /// düşük güvenli satırlar burada neredeyse her zaman arayüz gürültüsüdür (saat, pil ikonu).
    public let minimumConfidence: Double
    /// Yapısal belge tanıma (tablo/liste) denensin mi.
    public let usesDocumentStructure: Bool
    /// Barkod/QR taraması yapılsın mı.
    public let detectsBarcodes: Bool

    public init(
        languages: [String] = ["tr-TR", "en-US"],
        minimumConfidence: Double = 0.45,
        usesDocumentStructure: Bool = true,
        detectsBarcodes: Bool = true
    ) {
        self.languages = languages
        self.minimumConfidence = minimumConfidence
        self.usesDocumentStructure = usesDocumentStructure
        self.detectsBarcodes = detectsBarcodes
    }

    public static let `default` = OCRConfiguration()
}
