import Foundation

/// Bir ekran görüntüsünün ne olduğunu anlatan kapalı sınıf kümesi.
///
/// Küme bilinçli olarak **küçük ve kapalıdır**: Foundation Models guided generation'da
/// `@Generable` enum olarak yansıtılır, dolayısıyla model şema dışına çıkamaz. Yeni sınıf
/// eklemek `AnalysisSchemaVersion` artırmayı ve yeniden analizi gerektirir (05 §5).
public enum ShotCategory: String, Sendable, Codable, CaseIterable, Hashable {
    /// Fiş, fatura, ödeme makbuzu.
    case receipt
    /// Uçuş/otobüs/etkinlik bileti, biniş kartı, rezervasyon.
    case ticket
    /// Wifi ağ adı ve şifresi.
    case wifi
    /// Sohbet ekran görüntüsü (WhatsApp, iMessage, DM).
    case conversation
    /// Yemek tarifi, malzeme listesi.
    case recipe
    /// Haber/blog makalesi, uzun metin.
    case article
    /// Kaynak kodu, terminal çıktısı, hata mesajı.
    case code
    /// Ürün sayfası, fiyat, kampanya.
    case product
    /// Harita, adres, yol tarifi.
    case location
    /// Takvim etkinliği, davet, tarih içeren duyuru.
    case event
    /// Banka ekranı, IBAN, hesap özeti.
    case banking
    /// Kargo/sipariş takip ekranı.
    case shipping
    /// Kimlik, ehliyet, pasaport, üyelik kartı.
    case identity
    /// Yukarıdakilerden hiçbiri (meme, oyun, boş ekran).
    case other

    /// Kategorinin doğası gereği hassas veri taşıyıp taşımadığı.
    ///
    /// UI bu bayrağa bakarak detay ekranında metni varsayılan olarak katlar ve
    /// paylaşım seçeneklerini kısıtlar (KANON §7).
    public var isSensitiveByNature: Bool {
        switch self {
        case .banking, .identity, .wifi:
            return true
        case .receipt, .ticket, .conversation, .recipe, .article, .code,
             .product, .location, .event, .shipping, .other:
            return false
        }
    }

    /// Kullanıcının bir tarih bekleyeceği kategoriler — "Yaklaşan" widget'ı ve
    /// hatırlatıcı önerisi yalnız bunlarda öne çıkarılır.
    public var isTimeSensitive: Bool {
        switch self {
        case .ticket, .event, .shipping:
            return true
        case .receipt, .wifi, .conversation, .recipe, .article, .code,
             .product, .location, .banking, .identity, .other:
            return false
        }
    }
}
