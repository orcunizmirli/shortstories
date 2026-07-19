import Foundation
import Testing
@testable import AppFoundation

/// SS-143 — push payload parse'ının SAF doğrulamaları (gerçek APNs olmadan; deliverable 4). Tip gate:
/// yeni-bölüm + devam-et (F1) + coin-ödül + öneri (F2); bilinmeyen tip → nil (sessiz yok say). `type`
/// yoksa rota şeklinden coarse türetim (02 §5.6 tipsiz örnek). İçerik-ID doğrulaması burada YAPILMAZ
/// (rota düşürme/injection savunması aşağı akıştaki DeepLinkResolver'dadır; geçersiz-ID push'u yine parse
/// olur ki push_open atılabilsin).
struct PushPayloadTests {
    // MARK: - Kanonik camelCase wire sözleşmesi (07 §6.1 / 05 §1.7 "Wire formatı camelCase")

    /// SS-141 ORTA bulgu: kanonik backend payload'ı 07 §6.1 camelCase anahtarlar (`deeplink`,
    /// `campaignType`, `campaignId`) taşır. Parse bunu çözemezse push tap routing + NSE kategori
    /// atanmaz. 07 §6.1 örneğinin BİREBİR aynısı.
    @Test func canonicalCamelCaseNewEpisodeParses() throws {
        let payload = try #require(PushPayload(userInfo: [
            "campaignId": "newep_2026w28_a",
            "campaignType": "new_episode",
            "deeplink": "shortseries://series/srs_123/episode/12?t=0",
            "imageURL": "https://cdn.example.com/cover_srs_123.jpg"
        ]))
        #expect(payload.type == .newEpisode)
        #expect(payload.campaignID == "newep_2026w28_a")
        #expect(payload.route == URL(string: "shortseries://series/srs_123/episode/12?t=0"))
    }

    @Test func canonicalCamelCaseContinueParses() throws {
        let payload = try #require(PushPayload(userInfo: [
            "campaignId": "resume_x",
            "campaignType": "continue",
            "deeplink": "shortseries://play/srs_123?t=42"
        ]))
        #expect(payload.type == .continueWatching)
        #expect(payload.campaignID == "resume_x")
    }

    @Test func camelCaseSeriesIdParses() throws {
        let payload = try #require(PushPayload(userInfo: [
            "campaignType": "new_episode",
            "deeplink": "shortseries://series/srs_123/episode/13",
            "seriesId": "srs_123"
        ]))
        #expect(payload.seriesID == "srs_123")
    }

    @Test func camelCaseUnknownTypeIgnored() {
        // BİLİNMEYEN tip camelCase gelse de sessizce reddedilir (savunmacı gate korunur).
        #expect(PushPayload(userInfo: [
            "campaignType": "flash_sale",
            "deeplink": "shortseries://store/coins"
        ]) == nil)
    }

    // MARK: - F2 kampanya tipleri (SS-143 F2): coin-ödül + kişiselleştirilmiş öneri

    @Test func canonicalCamelCaseCoinRewardParsesToCoinRoute() throws {
        // Coin-ödül hatırlatma push'u → CoinMagazasi (`store/coins`); wire camelCase birincil.
        let payload = try #require(PushPayload(userInfo: [
            "campaignId": "coins_2026w29",
            "campaignType": "coin_reward",
            "deeplink": "shortseries://store/coins?offer=launch"
        ]))
        #expect(payload.type == .coinReward)
        #expect(payload.campaignID == "coins_2026w29")
        #expect(payload.route == URL(string: "shortseries://store/coins?offer=launch"))
    }

    @Test func coinRewardTargetsRewardsSurface() throws {
        // Coin-ödül push'u OdulMerkezi'ni de hedefleyebilir (`rewards/checkin`, 02 §8.2) — tip yine coinReward.
        let payload = try #require(PushPayload(userInfo: [
            "campaignType": "coin_reward",
            "deeplink": "shortseries://rewards/checkin"
        ]))
        #expect(payload.type == .coinReward)
        #expect(payload.route == URL(string: "shortseries://rewards/checkin"))
    }

    @Test func canonicalCamelCaseRecommendationParsesToSeriesRoute() throws {
        // Kişiselleştirilmiş öneri push'u → önerilen dizi DiziDetay (`series/{id}`); seriesId analitik taşır.
        let payload = try #require(PushPayload(userInfo: [
            "campaignId": "reco_srs_9f2c1a",
            "campaignType": "recommendation",
            "deeplink": "shortseries://series/srs_9f2c1a",
            "seriesId": "srs_9f2c1a"
        ]))
        #expect(payload.type == .recommendation)
        #expect(payload.campaignID == "reco_srs_9f2c1a")
        #expect(payload.route == URL(string: "shortseries://series/srs_9f2c1a"))
        #expect(payload.seriesID == "srs_9f2c1a")
    }

    @Test func legacySnakeCaseCoinRewardParses() throws {
        // Legacy snake_case sözleşmesi de köprülenir (savunmacı fallback) — regresyon koruması.
        let payload = try #require(PushPayload(userInfo: [
            "type": "coin_reward",
            "campaign_id": "coins_promo",
            "route": "shortseries://store/coins"
        ]))
        #expect(payload.type == .coinReward)
        #expect(payload.campaignID == "coins_promo")
        #expect(payload.route == URL(string: "shortseries://store/coins"))
    }

    @Test func legacySnakeCaseRecommendationParses() throws {
        let payload = try #require(PushPayload(userInfo: [
            "type": "recommendation",
            "route": "shortseries://series/srs_9f2c1a",
            "series_id": "srs_9f2c1a"
        ]))
        #expect(payload.type == .recommendation)
        #expect(payload.seriesID == "srs_9f2c1a")
    }

    @Test func recommendationInvalidContentIDStillParses() throws {
        // Deliverable 3: geçersiz içerik ID'li öneri push'u BURADA yine parse olur (route korunur) ki
        // `push_open` atılabilsin (08 §3.6, "mevcut kalıp"); rota düşürme/injection savunması aşağı
        // akıştaki `DeepLinkResolver` regex'indedir (DiscoverKit `invalidSeriesIDIsDropped`). PushPayload
        // içerik-ID doğrulaması YAPMAZ — bu ayrım atıf'ın rota geçersizken de atılmasını sağlar.
        let payload = try #require(PushPayload(userInfo: [
            "campaignType": "recommendation",
            "deeplink": "shortseries://series/DROP%20TABLE"
        ]))
        #expect(payload.type == .recommendation)
        #expect(payload.route == URL(string: "shortseries://series/DROP%20TABLE"))
    }

    @Test func camelCaseTypelessDeeplinkDerivesType() throws {
        // `campaignType` yok, yalnız `deeplink` → rota şeklinden coarse türetim.
        let payload = try #require(PushPayload(userInfo: [
            "deeplink": "shortseries://series/srs_123/episode/13",
            "campaignId": "new_ep"
        ]))
        #expect(payload.type == .newEpisode)
        #expect(payload.campaignID == "new_ep")
    }

    @Test func canonicalKeysWinOverLegacyWhenBothPresent() throws {
        // Sözleşme kanonik camelCase'tir; ikisi de gelirse otoriter anahtar kazanır (deterministik).
        let payload = try #require(PushPayload(userInfo: [
            "campaignType": "new_episode",
            "type": "continue",
            "deeplink": "shortseries://series/srs_123/episode/13",
            "route": "shortseries://play/srs_999?t=5",
            "campaignId": "canonical_id",
            "campaign_id": "legacy_id"
        ]))
        #expect(payload.type == .newEpisode)
        #expect(payload.route == URL(string: "shortseries://series/srs_123/episode/13"))
        #expect(payload.campaignID == "canonical_id")
    }

    // MARK: - Açık `type` (legacy snake_case sözleşmesi — regresyon koruması)

    @Test func explicitNewEpisodeParses() throws {
        let payload = try #require(PushPayload(userInfo: [
            "type": "new_episode",
            "campaign_id": "new_ep_2026_01",
            "route": "shortseries://series/srs_123/episode/13",
            "series_id": "srs_123"
        ]))
        #expect(payload.type == .newEpisode)
        #expect(payload.campaignID == "new_ep_2026_01")
        #expect(payload.route == URL(string: "shortseries://series/srs_123/episode/13"))
        #expect(payload.seriesID == "srs_123")
    }

    @Test func explicitContinueParses() throws {
        let payload = try #require(PushPayload(userInfo: [
            "type": "continue",
            "campaign_id": "resume_x",
            "route": "shortseries://play/srs_123?t=42"
        ]))
        #expect(payload.type == .continueWatching)
        #expect(payload.campaignID == "resume_x")
        #expect(payload.seriesID == nil)
    }

    // MARK: - Bilinmeyen tip → nil (sessiz yok say; F1/F2 dışı kalır)

    @Test func unknownTypeIgnored() {
        #expect(PushPayload(userInfo: [
            "type": "flash_sale",
            "route": "shortseries://home"
        ]) == nil)
    }

    @Test func unknownVipUpsellTypeIgnored() {
        // F2 iki tip ekler (coin_reward/recommendation); başka her tip HÂLÂ reddedilir (savunmacı).
        #expect(PushPayload(userInfo: [
            "type": "vip_upsell",
            "route": "shortseries://store/vip"
        ]) == nil)
    }

    // MARK: - Eksik/bozuk alanlar → nil

    @Test func missingRouteIsNil() {
        #expect(PushPayload(userInfo: ["type": "new_episode", "campaign_id": "x"]) == nil)
    }

    @Test func emptyRouteIsNil() {
        #expect(PushPayload(userInfo: ["type": "new_episode", "route": ""]) == nil)
    }

    @Test func nonStringRouteIsNil() {
        #expect(PushPayload(userInfo: ["type": "new_episode", "route": 42]) == nil)
    }

    // MARK: - `type` taşımayan payload → rota şeklinden türetim (02 §5.6)

    @Test func typelessEpisodeRouteDerivesNewEpisode() throws {
        // 02 §5.6 örnek payload: {"route": "...episode/13", "campaign_id": "new_ep"} (type YOK).
        let payload = try #require(PushPayload(userInfo: [
            "route": "shortseries://series/srs_123/episode/13",
            "campaign_id": "new_ep"
        ]))
        #expect(payload.type == .newEpisode)
        #expect(payload.campaignID == "new_ep")
    }

    @Test func typelessPlayRouteDerivesContinue() throws {
        let payload = try #require(PushPayload(userInfo: [
            "route": "shortseries://play/srs_123?t=90"
        ]))
        #expect(payload.type == .continueWatching)
    }

    @Test func typelessUniversalEpisodeRouteDerivesNewEpisode() throws {
        let payload = try #require(PushPayload(userInfo: [
            "route": "https://shortseries.app/s/srs_123/e/4"
        ]))
        #expect(payload.type == .newEpisode)
    }

    @Test func typelessUnknownRouteIsNil() {
        // type yok + türetilebilir şekil yok (ör. discover) → nil (F1 gate).
        #expect(PushPayload(userInfo: ["route": "shortseries://discover"]) == nil)
    }

    @Test func emptyTypeFallsBackToRouteDerivation() throws {
        // Boş `type` string'i eksik sayılır → rota'dan türetilir.
        let payload = try #require(PushPayload(userInfo: [
            "type": "",
            "route": "shortseries://play/srs_123"
        ]))
        #expect(payload.type == .continueWatching)
    }
}

/// SS-140 — APNs `Data` → hex `DeviceToken` dönüşümü.
struct DeviceTokenTests {
    @Test func rawDataEncodesToLowercaseHex() {
        let token = DeviceToken(rawTokenData: Data([0x01, 0xAB, 0xFF, 0x00, 0x10]))
        #expect(token.hexString == "01abff0010")
    }

    @Test func emptyDataEncodesToEmptyString() {
        #expect(DeviceToken(rawTokenData: Data()).hexString == "")
    }

    @Test func hexStringInitPreservesValue() {
        #expect(DeviceToken(hexString: "deadbeef").hexString == "deadbeef")
    }
}
