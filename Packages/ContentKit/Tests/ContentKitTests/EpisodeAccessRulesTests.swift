import Foundation
import Testing
@testable import ContentKit

/// EpisodeAccess kural testleri (05 §2.2) — davranış testleri domain adlarıyla.
struct EpisodeAccessRulesTests {
    @Test func freeBolumKilitsizOynatilabilir() {
        let access = EpisodeAccess(kind: .free, unlockPrice: nil, adUnlockEligible: false)

        #expect(access.isPlayableWithoutUnlock)
        #expect(!access.isCoinUnlockAvailable)
        #expect(!access.isCoinPathClosedLock)
    }

    @Test func unlockedBolumKilitsizOynatilabilir() {
        // `unlocked`: bu kullanıcı için açılmış kilitli bölüm (VIP'e sunucu free/unlocked döner)
        let access = EpisodeAccess(kind: .unlocked, unlockPrice: nil, adUnlockEligible: false)

        #expect(access.isPlayableWithoutUnlock)
        #expect(!access.isCoinUnlockAvailable)
    }

    @Test func fiyatliKilitCoinYoluAcik() {
        let access = EpisodeAccess(kind: .locked, unlockPrice: 60, adUnlockEligible: true)

        #expect(!access.isPlayableWithoutUnlock)
        #expect(access.isCoinUnlockAvailable)
        #expect(!access.isCoinPathClosedLock)
        #expect(access.adUnlockEligible)
    }

    /// Genişleme noktası (05 §2.2): kind == .locked + unlockPrice == null geçerlidir ve
    /// "coin ile açılamaz" demektir (örn. salt-VIP içerik). UnlockSheet coin satırı çizmez.
    @Test func fiyatsizKilitCoinYoluKapali() {
        let access = EpisodeAccess(kind: .locked, unlockPrice: nil, adUnlockEligible: false)

        #expect(!access.isPlayableWithoutUnlock)
        #expect(!access.isCoinUnlockAvailable)
        #expect(access.isCoinPathClosedLock)
    }

    /// 05 §12 kural 4: `.unknown` kind kilitli varsayılır (güvenli taraf);
    /// gerçek durumu `POST /playback/authorize` çözer.
    @Test func bilinmeyenKindKilitliVarsayilir() {
        let access = EpisodeAccess(kind: .unknown, unlockPrice: nil, adUnlockEligible: false)

        #expect(!access.isPlayableWithoutUnlock)
        #expect(!access.isCoinUnlockAvailable)
        #expect(!access.isCoinPathClosedLock) // coin-yolu-kapalı semantiği yalnız .locked için
    }

    /// unlockPrice yalnız .locked iken anlamlıdır (05 §2.2 tablo).
    @Test func unlockPriceYalnizLockedIkenAnlamli() {
        let access = EpisodeAccess(kind: .unlocked, unlockPrice: 60, adUnlockEligible: false)

        #expect(!access.isCoinUnlockAvailable)
    }

    // MARK: - Release schedule (SS-033)

    @Test func publishedAtNullBolumYayinlanmamis() throws {
        let page = try Fixtures.decode(PageWire<EpisodeWire>.self, from: "episodes_page")
        let unreleased = page.items[4].toDomain()

        #expect(unreleased.publishedAt == nil)
        #expect(!unreleased.isPublished(at: isoDate("2026-07-11T00:00:00Z")))
    }

    @Test func gelecekTarihliBolumHenuzYayinlanmamis() throws {
        let page = try Fixtures.decode(PageWire<EpisodeWire>.self, from: "episodes_page")
        let released = page.items[0].toDomain() // publishedAt: 2026-05-01

        #expect(released.isPublished(at: isoDate("2026-07-11T00:00:00Z")))
        #expect(!released.isPublished(at: isoDate("2026-04-30T00:00:00Z")))
    }
}
