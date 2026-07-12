import Foundation
import Testing
@testable import AppFoundation

struct FeatureFlagStoreTests {
    private let boolFlag = FlagKey(name: "test.bool", default: false)
    private let intFlag = FlagKey(name: "test.int", default: 5)
    private let doubleFlag = FlagKey(name: "test.double", default: 0.5)
    private let stringFlag = FlagKey(name: "test.string", default: "varsayilan")

    @Test func snapshotDegerleriOkunur() {
        let store = FeatureFlagStore(snapshot: [
            "test.bool": .bool(true),
            "test.int": .int(9),
            "test.double": .double(1.5),
            "test.string": .string("canli")
        ])
        #expect(store.value(for: boolFlag) == true)
        #expect(store.value(for: intFlag) == 9)
        #expect(store.value(for: doubleFlag) == 1.5)
        #expect(store.value(for: stringFlag) == "canli")
    }

    @Test func eksikAnahtarKodIciVarsayilanaDuser() {
        let store = FeatureFlagStore(snapshot: [:])
        #expect(store.value(for: boolFlag) == false)
        #expect(store.value(for: intFlag) == 5)
        #expect(store.value(for: doubleFlag) == 0.5)
        #expect(store.value(for: stringFlag) == "varsayilan")
    }

    @Test func tipUyusmazligiVarsayilanaDuser() {
        let store = FeatureFlagStore(snapshot: ["test.int": .string("dokuz")])
        #expect(store.value(for: intFlag) == 5)
    }

    @Test func intSnapshotDoubleAnahtariniBesler() {
        // Config 2.0 yerine 2 gönderebilir; double anahtar int değeri kabul eder.
        let store = FeatureFlagStore(snapshot: ["test.double": .int(2)])
        #expect(store.value(for: doubleFlag) == 2.0)
    }

    @Test func userDefaultsRoundTrip() throws {
        let suiteName = "FeatureFlagStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FeatureFlagStore.persistSnapshot([
            "test.bool": .bool(true),
            "test.int": .int(7),
            "test.double": .double(2.5),
            "test.string": .string("kayitli")
        ], to: defaults)

        let store = FeatureFlagStore(userDefaults: defaults)
        #expect(store.value(for: boolFlag) == true)
        #expect(store.value(for: intFlag) == 7)
        #expect(store.value(for: doubleFlag) == 2.5)
        #expect(store.value(for: stringFlag) == "kayitli")
    }

    @Test func bosDefaultsVarsayilanlariDondurur() throws {
        let suiteName = "FeatureFlagStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FeatureFlagStore(userDefaults: defaults)
        #expect(store.value(for: intFlag) == 5)
    }

    @Test func kanonikFlagSabitleri() {
        // 03 §11 örnekleriyle birebir.
        #expect(Flags.rewardedDailyCap.name == "rewards.daily_ad_cap")
        #expect(Flags.rewardedDailyCap.default == 5)
        #expect(Flags.dataSaverMaxHeight.name == "player.data_saver_max_height")
        #expect(Flags.dataSaverMaxHeight.default == 480)
    }
}
