import Foundation

/// Push kampanya tipi (SS-143; 08 §3.6 `push_open.push_type`). F1 kapsamı yeni-bölüm + devam-et
/// (01 NTF-02 Must); F2 kapsamı coin-ödül + kişiselleştirilmiş öneri (Should). BİLİNMEYEN tip HÂLÂ
/// `PushPayload` parse'ında sessizce reddedilir (bilinmeyen → payload `nil`; savunmacı). rawValue'lar
/// 08 `push_type` enum'uyla birebir (`"new_episode"|"continue"|"coin_reward"|"recommendation"`).
public enum PushCampaignType: String, Sendable, Equatable, CaseIterable {
    /// Yeni bölüm yayında (02 §5.6) — hedef `series/{id}/episode/{n}`.
    case newEpisode = "new_episode"
    /// Kaldığın yerden devam (02 §8.2 `play?t=`) — hedef `play/{id}?t={sec}`.
    case continueWatching = "continue"
    /// Coin/ödül hatırlatması (F2; 08 §3.6 `"coin_reward"`) — hedef coin/ödül yüzeyi: `store/coins`
    /// (CoinMagazasi, 02 §8.2) veya `rewards[/checkin]` (OdulMerkezi). Sabit-path hedef; içerik ID yok.
    case coinReward = "coin_reward"
    /// Kişiselleştirilmiş öneri (F2; 08 §3.6 `"recommendation"`) — hedef önerilen dizi `series/{id}`
    /// (DiziDetay); `seriesId` payload'da analitik için taşınır, ID doğrulaması rota çözümünde yapılır.
    /// Wire `rawValue` = case adı (`"recommendation"`); redundantRawValues gereği açık yazılmaz.
    case recommendation
}

/// APNs push payload'ının uygulama-alanı değer tipi (SS-143). `UNUserNotificationCenter`'dan gelen ham
/// `userInfo` sözlüğünü çözer; UN tipleri App delegate seam'inde kalır — bu tip yalnız Foundation taşır.
/// Parse SAF ve deterministiktir (gerçek APNs olmadan test edilir, deliverable 4).
///
/// TİP GATE: yeni-bölüm + devam-et (F1) + coin-ödül + öneri (F2); BİLİNMEYEN/eksik tip → `nil`
/// (sessiz yok say, 02 §5.6 hata dalı). İçerik ID doğrulaması BURADA YAPILMAZ (geçersiz-ID rota da
/// parse olur ki `push_open` atılabilsin, 08 §3.6); injection savunması + rota düşürme aşağı akıştaki
/// `DeepLinkRoute(url:)`/`DeepLinkResolver`'dadır (02 §8.4 kural 4). Kanonik payload sözleşmesi
/// (07 §6.1 + 05 §1.7 "Wire formatı camelCase"):
/// `deeplink` (deep link, zorunlu), `campaignType` (kampanya tipi discriminator), `campaignId` (atıf),
/// `seriesId` (opsiyonel analitik). Parse SAVUNMACIDIR: harici/güvenilmeyen backend girdisi olduğu
/// için legacy snake_case anahtarlar (`route`/`type`/`campaign_id`/`series_id`) da köprülenir (SS-141
/// görsel anahtarı `imageURL`/`image_url`/`image` ile aynı desen). `campaignType` taşımayan payload →
/// tip rota şeklinden coarse türetilir (aşağıda).
public struct PushPayload: Sendable, Equatable {
    /// Kampanya tipi (analitik `push_type`).
    public let type: PushCampaignType
    /// Kampanya kimliği (kanonik payload `campaignId`; analitik `campaign_id`). Opsiyonel.
    public let campaignID: String?
    /// Deep link hedefi (kanonik payload `deeplink`; `shortseries://...` veya universal link).
    public let route: URL
    /// Analitik `series_id` (opsiyonel; payload'da yoksa App çözülmüş rota'dan türetir).
    public let seriesID: String?

    public init(type: PushCampaignType, campaignID: String?, route: URL, seriesID: String? = nil) {
        self.type = type
        self.campaignID = campaignID
        self.route = route
        self.seriesID = seriesID
    }

    /// Deep link rota anahtar adayları — kanonik `deeplink` (07 §6.1) birincil; `route` legacy fallback.
    private static let routeKeys = ["deeplink", "route"]
    /// Kampanya tipi anahtar adayları — kanonik `campaignType` birincil; `type` legacy fallback.
    private static let typeKeys = ["campaignType", "type"]
    /// Kampanya kimliği anahtar adayları — kanonik `campaignId` birincil; `campaign_id` legacy fallback.
    private static let campaignIDKeys = ["campaignId", "campaign_id"]
    /// Analitik series kimliği anahtar adayları — kanonik `seriesId` birincil; `series_id` legacy fallback.
    private static let seriesIDKeys = ["seriesId", "series_id"]

    /// APNs `userInfo` sözlüğünden çözer. Rota (`deeplink`/`route`) ZORUNLU; tip (`campaignType`/`type`)
    /// açıksa onu kullanır (F1+F2 tipleri çözülür, bilinmeyen → `nil`), yoksa rota şeklinden türetir
    /// (07 §6.2 tipsiz örnek).
    /// Kanonik camelCase birincil, legacy snake_case fallback (savunmacı köprüleme). Çözülemezse `nil`.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let routeString = Self.string(forKeys: Self.routeKeys, in: userInfo),
              let route = URL(string: routeString),
              let type = Self.resolveType(
                  explicit: Self.string(forKeys: Self.typeKeys, in: userInfo),
                  route: route
              )
        else { return nil }
        self.init(
            type: type,
            campaignID: Self.string(forKeys: Self.campaignIDKeys, in: userInfo),
            route: route,
            seriesID: Self.string(forKeys: Self.seriesIDKeys, in: userInfo)
        )
    }

    /// Anahtar adaylarını SIRAYLA dener; ilk boş-olmayan `String` değerini döndürür (kanonik önce),
    /// hiçbiri yoksa `nil`. Sözleşme drift'ine karşı savunmacı köprü (SS-141 `imageKeys` deseni).
    private static func string(forKeys keys: [String], in userInfo: [AnyHashable: Any]) -> String? {
        for key in keys {
            if let value = string(userInfo[key]) {
                return value
            }
        }
        return nil
    }

    /// Boş olmayan `String` değerini çıkarır; diğer tip/boş/eksik → `nil`.
    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    /// Açık `type` varsa onu döner (F1 dışı `rawValue` → `nil`); yoksa rota şeklinden coarse türetir.
    static func resolveType(explicit: String?, route: URL) -> PushCampaignType? {
        if let explicit {
            // new_episode/continue (F1) + coin_reward/recommendation (F2) → çözülür; bilinmeyen → nil.
            return PushCampaignType(rawValue: explicit)
        }
        return derivedType(from: route)
    }

    /// Rota'nın ilk mantıksal segmentinden coarse tip — yalnız `type` taşımayan payload'lar için
    /// FALLBACK. `series`/`s` → yeni bölüm; `play` → devam-et; diğer → `nil`. Tam çözüm App'te
    /// `DeepLinkRoute(url:)` ile yapılır (bu yalnız analitik `push_type` içindir).
    static func derivedType(from route: URL) -> PushCampaignType? {
        switch firstSegment(of: route) {
        case "series", "s": .newEpisode
        case "play": .continueWatching
        default: nil
        }
    }

    /// Rota'nın ilk mantıksal segmenti: custom scheme'de host (`shortseries://series/...`),
    /// universal link'te ilk path segmenti (`https://shortseries.app/s/...`).
    private static func firstSegment(of url: URL) -> String? {
        let firstPathSegment = url.path.split(separator: "/").first.map(String.init)?.lowercased()
        switch url.scheme?.lowercased() {
        case "https", "http":
            return firstPathSegment
        default:
            if let host = url.host, !host.isEmpty {
                return host.lowercased()
            }
            return firstPathSegment
        }
    }
}
