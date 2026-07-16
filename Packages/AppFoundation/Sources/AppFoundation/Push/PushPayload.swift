import Foundation

/// F1 push kampanya tipi (SS-143; 08 §3.6 `push_open.push_type`). YALNIZ yeni-bölüm ve devam-et
/// F1 kapsamındadır (01 NTF-02 Must); coin-ödül/öneri F2'dir (Should) ve `PushPayload` parse'ında
/// SESSİZCE reddedilir (bilinmeyen/F2 tip → payload `nil`). rawValue'lar 08 `push_type` enum'uyla birebir.
public enum PushCampaignType: String, Sendable, Equatable, CaseIterable {
    /// Yeni bölüm yayında (02 §5.6) — hedef `series/{id}/episode/{n}`.
    case newEpisode = "new_episode"
    /// Kaldığın yerden devam (02 §8.2 `play?t=`) — hedef `play/{id}?t={sec}`.
    case continueWatching = "continue"
}

/// APNs push payload'ının uygulama-alanı değer tipi (SS-143). `UNUserNotificationCenter`'dan gelen ham
/// `userInfo` sözlüğünü çözer; UN tipleri App delegate seam'inde kalır — bu tip yalnız Foundation taşır.
/// Parse SAF ve deterministiktir (gerçek APNs olmadan test edilir, deliverable 4).
///
/// F1 GATE (task kapsamı): yalnız yeni-bölüm + devam-et; diğer/eksik tip → `nil` (sessiz yok say,
/// 02 §5.6 hata dalı). Payload sözleşmesi (SS-141): `route` (deep link, zorunlu), `type` (kampanya
/// tipi discriminator), `campaign_id` (atıf), `series_id` (opsiyonel analitik). 02 §5.6 örneği `type`
/// taşımayabilir → tip o durumda rota şeklinden coarse türetilir (aşağıda).
public struct PushPayload: Sendable, Equatable {
    /// Kampanya tipi (analitik `push_type`).
    public let type: PushCampaignType
    /// Kampanya kimliği (analitik `campaign_id`; 02 §5.6 payload `campaign_id`). Opsiyonel.
    public let campaignID: String?
    /// Deep link hedefi (02 §5.6 payload `route`; `shortseries://...` veya universal link).
    public let route: URL
    /// Analitik `series_id` (opsiyonel; payload'da yoksa App çözülmüş rota'dan türetir).
    public let seriesID: String?

    public init(type: PushCampaignType, campaignID: String?, route: URL, seriesID: String? = nil) {
        self.type = type
        self.campaignID = campaignID
        self.route = route
        self.seriesID = seriesID
    }

    /// APNs `userInfo` sözlüğünden çözer. `route` ZORUNLU; `type` açıksa onu kullanır (F2/bilinmeyen →
    /// `nil`), yoksa rota şeklinden türetir (02 §5.6 tipsiz örnek). Çözülemezse `nil`.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let routeString = Self.string(userInfo["route"]),
              let route = URL(string: routeString),
              let type = Self.resolveType(explicit: Self.string(userInfo["type"]), route: route)
        else { return nil }
        self.init(
            type: type,
            campaignID: Self.string(userInfo["campaign_id"]),
            route: route,
            seriesID: Self.string(userInfo["series_id"])
        )
    }

    /// Boş olmayan `String` değerini çıkarır; diğer tip/boş/eksik → `nil`.
    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    /// Açık `type` varsa onu döner (F1 dışı `rawValue` → `nil`); yoksa rota şeklinden coarse türetir.
    static func resolveType(explicit: String?, route: URL) -> PushCampaignType? {
        if let explicit {
            // coin_reward/recommendation/bilinmeyen → nil (F1 sessiz reddi).
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
