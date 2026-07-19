import Foundation

/// Uygulama-içi bildirim kimliği (NTF-04). `SeriesID`/`EpisodeID` (AppFoundation) ile aynı
/// `RawRepresentable` desenidir: sunucunun düz string `id`si domain tipine sorunsuz decode olur
/// (05 §1.7 wire→domain sınırı). ProfileKit-yerel (BildirimMerkezi'ne özgü opak kimlik).
public struct NotificationID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Uygulama-içi bildirim tipi (NTF-04; satır ikonunu belirler, hedefi DEĞİL). rawValue'lar push
/// kampanya tipleriyle (08 §3.6 `push_type`) HİZALIDIR — `new_episode|continue|coin_reward|
/// recommendation` — artı BildirimMerkezi'ne özgü `reward` (ödül hatırlatması) ve `campaign`
/// (kampanya/duyuru) tipleri (01 NTF-04: "yeni bölüm, ödül, kampanya").
///
/// R2: AppFoundation `PushCampaignType` İMPORT EDİLMEZ (Push modeli taşınmaz) — enum ProfileKit-
/// yereldir, yalnız rawValue'larla push tipleriyle hizalanır. Tip enum'u ProfileKit-yerel tutulur ki
/// BildirimMerkezi push kanalından bağımsız evrilebilsin.
///
/// SAVUNMACI (ileri-uyumluluk): sunucu ileride yeni bir tip eklerse öğe DÜŞÜRÜLMEZ — bilinmeyen
/// rawValue `.unknown`'a düşer, jenerik ikonla listelenir; satır tap'ı yine `route` ile sürer.
/// Bu, `PushPayload`'ın "bilinmeyen tip → nil (push düşer)" gate'inden BİLİNÇLİ ayrışır: yönlendirilemeyen
/// push atılır, ama listelenen bir kayıt zaten route taşır ve retention yüzeyi olarak korunmalıdır.
public enum NotificationType: String, Sendable, Equatable, Decodable {
    /// Yeni bölüm yayında (hedef `series/{id}/episode/{n}`).
    case newEpisode = "new_episode"
    /// Kaldığın yerden devam (hedef `play/{id}?t=`).
    case continueWatching = "continue"
    /// Coin/ödül hatırlatması push'u (hedef coin/ödül yüzeyi: `store/coins` veya `rewards`).
    case coinReward = "coin_reward"
    /// Kişiselleştirilmiş öneri (hedef önerilen dizi `series/{id}`).
    case recommendation
    /// Ödül hatırlatması (OdulMerkezi check-in/streak; push kanalından bağımsız da üretilebilir).
    case reward
    /// Kampanya/duyuru (promosyon; hedef kampanya yüzeyi veya store).
    case campaign
    /// İleri-uyumluluk: bilinmeyen sunucu tipi (öğe korunur, jenerik ikon).
    case unknown

    /// Bilinmeyen rawValue → `.unknown` (savunmacı; öğe düşürülmez, 05 §2.12 "bilinmeyen tip"
    /// yumuşak ele alma ilkesi). `SuggestionWire.toDomain` bilinmeyen-tip-korunur deseniyle aynı.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NotificationType(rawValue: raw) ?? .unknown
    }
}

/// Uygulama-içi bildirim değer tipi (NTF-04; `GET /notifications` sayfa öğesi, 05 §13 taslak).
/// Push'a paralel ikinci retention yüzeyi: her push kampanya kaydı burada da listelenir ve satır
/// dokunuşu push ile AYNI `route`'u izler (NTF-04 kabul kriteri).
///
/// `route` DIŞ-BAĞIMLILIK SINIRIDIR: ham deep-link String taşınır. ProfileKit DiscoverKit/Route
/// enum'unu GÖRMEZ (R2) — çözüm + geçersiz-hedef fallback'i App'te `Route(url:)`/`DeepLinkResolver`'da
/// (02 §8.4). Böylece BildirimMerkezi navigasyon grafiğinden bağımsızdır.
///
/// Decodable: wire `camelCase` birincildir (05 §1.7 `useDefaultKeys` — property adları = wire adları).
/// `createdAt` ISO 8601 UTC'dir ve `JSONDecoder.shortSeriesDefault` ile okunur (fractional saniye
/// dahil). `type` bilinmeyen rawValue'da `.unknown`'a düşer (savunmacı).
public struct AppNotification: Sendable, Equatable, Identifiable, Decodable {
    public let id: NotificationID
    public let type: NotificationType
    public let title: String
    public let body: String
    /// Sunucu-tarafı oluşturma zamanı (05 §1.7 ISO 8601 UTC). Liste en yeni önce sıralı gelir
    /// (sunucu sözleşmesi); istemci ayrıca sıralamaz.
    public let createdAt: Date
    /// Push ile AYNI ham deep-link rotası (NTF-04). App çözer; ProfileKit yorumlamaz.
    public let route: String
    /// Okunma durumu — `markRead`/`markAllRead` optimistik olarak çevirir; wire'dan gelir.
    public private(set) var isRead: Bool

    public init(
        id: NotificationID,
        type: NotificationType,
        title: String,
        body: String,
        createdAt: Date,
        route: String,
        isRead: Bool
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.route = route
        self.isRead = isRead
    }

    /// Rota YAPISAL olarak dolu mu — App'in `Route(url:)` çözümüne aday. Boş/whitespace route App'te
    /// çözülemez → doğrudan `Kesfet` fallback'ine işaretlenir (02 §4.15 geçersiz-hedef + §8.4 kuralı).
    /// ProfileKit Route enum'unu GÖRMEDİĞİNDEN yalnız yapısal boşluğu ayırt eder; nihai geçerlilik
    /// (dizi kaldırıldı vb.) App'te `DeepLinkResolver`'da belirlenir.
    public var hasRoute: Bool {
        !route.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `isRead` değişmiş bir KOPYA döndürür (değer semantiği). Model okundu-çevirmelerini bununla
    /// yapar; harici optimistik UI de kullanabilir (`private(set)` doğrudan yazımı kapatır).
    public func withRead(_ isRead: Bool) -> AppNotification {
        var copy = self
        copy.isRead = isRead
        return copy
    }
}
