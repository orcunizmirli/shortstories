import Foundation
import Testing
@testable import AppFoundation

/// SS-143 — push payload parse'ının SAF doğrulamaları (gerçek APNs olmadan; deliverable 4). F1 gate:
/// yalnız yeni-bölüm + devam-et; F2/bilinmeyen tip → nil (sessiz yok say). `type` yoksa rota şeklinden
/// coarse türetim (02 §5.6 tipsiz örnek).
struct PushPayloadTests {
    // MARK: - Açık `type` (kanonik sözleşme)

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

    // MARK: - F2 / bilinmeyen tip → nil (sessiz yok say)

    @Test func coinRewardTypeIgnored() {
        #expect(PushPayload(userInfo: [
            "type": "coin_reward",
            "route": "shortseries://store/coins"
        ]) == nil)
    }

    @Test func recommendationTypeIgnored() {
        #expect(PushPayload(userInfo: [
            "type": "recommendation",
            "route": "shortseries://series/srs_123"
        ]) == nil)
    }

    @Test func unknownTypeIgnored() {
        #expect(PushPayload(userInfo: [
            "type": "flash_sale",
            "route": "shortseries://home"
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
