import Foundation
import Testing
@testable import AppFoundation

struct RemoteConfigDecodingTests {
    /// Canlı APIClient ile AYNI decoder (camelCase + ISO 8601) — wire fidelity.
    private let decoder = JSONDecoder.shortSeriesDefault()

    private func decode(_ json: String) throws -> RemoteConfig {
        try decoder.decode(RemoteConfig.self, from: Data(json.utf8))
    }

    @Test func tamSozlesmeCozulur() throws {
        // 05 §4.10 örneğiyle birebir.
        let config = try decode(
            """
            {
              "minSupportedVersion": "1.0.0",
              "coinProducts": ["com.shortseries.coins.tier1", "com.shortseries.coins.tier2"],
              "vipProducts": ["com.shortseries.vip.weekly", "com.shortseries.vip.yearly"],
              "adUnlockDailyCap": 5,
              "flags": { "rewardedAdsEnabled": false, "fairplayEnabled": false, "liveActivitiesEnabled": true },
              "experiments": [ { "key": "paywall_layout", "variant": "B" } ]
            }
            """
        )
        #expect(config.minSupportedVersion == "1.0.0")
        #expect(config.coinProducts == ["com.shortseries.coins.tier1", "com.shortseries.coins.tier2"])
        #expect(config.vipProducts == ["com.shortseries.vip.weekly", "com.shortseries.vip.yearly"])
        #expect(config.adUnlockDailyCap == 5)
        #expect(config.flags["rewardedAdsEnabled"] == .bool(false))
        #expect(config.flags["fairplayEnabled"] == .bool(false))
        #expect(config.flags["liveActivitiesEnabled"] == .bool(true))
        #expect(config.experiments == [RemoteExperimentAssignment(key: "paywall_layout", variant: "B")])
    }

    @Test func eksikAlanlarKodIciVarsayilanaDuser() throws {
        // 03 §11: config gelmezse uygulama varsayılanla tam çalışır.
        let config = try decode("{}")
        #expect(config.minSupportedVersion == "0.0.0")
        #expect(config.coinProducts.isEmpty)
        #expect(config.vipProducts.isEmpty)
        #expect(config.adUnlockDailyCap == 5)
        #expect(config.flags.isEmpty)
        #expect(config.experiments.isEmpty)
    }

    @Test func kismenEksikAlanKalanlariEtkilemez() throws {
        let config = try decode(#"{ "adUnlockDailyCap": 8 }"#)
        #expect(config.adUnlockDailyCap == 8)
        #expect(config.minSupportedVersion == "0.0.0")
        #expect(config.flags.isEmpty)
    }

    @Test func flagHeterojenSkalerlereKoprulenir() throws {
        // bool/int/double/string ayrımı; JSON false Int'e DÜŞMEZ, tam sayı Double'dan önce.
        let config = try decode(
            """
            {
              "flags": {
                "boolFlag": true,
                "intFlag": 7,
                "doubleFlag": 1.5,
                "stringFlag": "v2"
              }
            }
            """
        )
        #expect(config.flags["boolFlag"] == .bool(true))
        #expect(config.flags["intFlag"] == .int(7))
        #expect(config.flags["doubleFlag"] == .double(1.5))
        #expect(config.flags["stringFlag"] == .string("v2"))
    }

    @Test func birdenCokDeneyAtamasiCozulur() throws {
        let config = try decode(
            """
            {
              "experiments": [
                { "key": "paywall_layout", "variant": "B" },
                { "key": "onboarding_flow", "variant": "control" }
              ]
            }
            """
        )
        #expect(config.experiments.count == 2)
        #expect(config.experiments[0] == RemoteExperimentAssignment(key: "paywall_layout", variant: "B"))
        #expect(config.experiments[1] == RemoteExperimentAssignment(key: "onboarding_flow", variant: "control"))
    }

    @Test func bozukFlagDegeriHataFirlatir() {
        // Desteklenmeyen flag değeri (dizi) gerçek decoding hatası olarak yüzer.
        #expect(throws: (any Error).self) {
            try decode(#"{ "flags": { "bad": [1, 2] } }"#)
        }
    }

    @Test func tipceUyumsuzZorunluAlanHataFirlatir() {
        // adUnlockDailyCap bir string olarak gelirse decodeIfPresent tip hatası fırlatır
        // (varsayılana SESSİZCE düşmez — bozuk yük graceful katmanda yakalanır).
        #expect(throws: (any Error).self) {
            try decode(#"{ "adUnlockDailyCap": "five" }"#)
        }
    }

    @Test func cacheRoundTripAlanlariKorur() throws {
        // Cache encode → decode kaybı yok (RemoteConfig Codable, FlagRawValue köprüsü).
        let original = RemoteConfig(
            minSupportedVersion: "2.3.4",
            coinProducts: ["c1"],
            vipProducts: ["v1"],
            adUnlockDailyCap: 9,
            flags: ["a": .bool(true), "b": .int(3), "c": .double(2.5), "d": .string("x")],
            experiments: [RemoteExperimentAssignment(key: "k", variant: "V")]
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(RemoteConfig.self, from: data)
        #expect(restored == original)
    }
}
