import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

/// DiziDetayModel entitlement-gözlem (bug-hunt #2): DiziDetay AÇIKKEN unlock/VIP olursa erişim kümesi + CTA
/// kilidi yeniden türetilmeli. Aksi halde kullanıcı ödediği bölüm için CTA 🔒 kalıp UnlockSheet'i tekrar
/// açardı (zaten sahip olduğu içerik). Reaktif self-gözlem: coordinator wiring gerekmez.
@MainActor
@Suite("DiziDetayModel entitlement gözlem")
struct DiziDetayEntitlementObserveTests {
    private let seriesID = SeriesID("srs_abc123")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 1-2 ücretsiz, 3-5 kilitli (unlockPrice 50). İlerleme Bölüm 3'te (yarım) → CTA hedefi Bölüm 3 (kilitli).
    private func lockedSeriesCatalog() -> SpyCatalog {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(Fixtures.series(
            id: "srs_abc123", episodeCount: 5, releasedEpisodeCount: 5, freeEpisodeCount: 2
        )))
        let episodes =
            (1 ... 2).map { Fixtures.episode(seriesID: "srs_abc123", index: $0, access: .free) } +
            (3 ... 5).map { Fixtures.episode(seriesID: "srs_abc123", index: $0, access: .locked, unlockPrice: 50) }
        spy.setEpisodes(.success(Page(items: episodes, nextCursor: nil, ttlSec: nil)))
        return spy
    }

    @Test func unlockSinyaliCTAKilidiniVeErisimKumesiniYenidenTuretir() async throws {
        let spy = lockedSeriesCatalog()
        let entitlement = FakeEntitlements() // başta hiçbir kilitliye erişim yok
        let changes = ManualEntitlementChanges()
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 3, completed: false))
        let model = DiziDetayModel(
            seriesID: seriesID,
            source: .kesfet,
            catalog: spy,
            history: history,
            favorites: FakeFavorites(),
            entitlement: entitlement,
            analytics: MockAnalytics(),
            delegate: nil,
            entitlementChanges: changes,
            now: { now }
        )

        model.onAppear()
        await model.pendingWork()
        let episode3Cell = try #require(model.episodes.first { $0.index == 3 })

        // Başlangıç: Bölüm 3 kilitli → CTA kilitli, hücre .locked.
        #expect(model.ctaLocked)
        #expect(model.cellState(for: episode3Cell) == .locked(price: 50))

        // Kullanıcı Bölüm 3'ü açar (entitlement erişim verir) + değişim sinyali yayılır.
        entitlement.grant(EpisodeID("srs_abc123_e3"))
        changes.emit()

        // Gözlemci recomputeAccess çalıştırana dek bekle (sınırlı poll — asılmaz).
        for _ in 0 ..< 1000 where model.ctaLocked {
            await Task.yield()
        }

        #expect(!model.ctaLocked) // CTA artık kilitli değil → "İzlemeye Başla/Devam Et" oynatabilir
        #expect(model.cellState(for: episode3Cell) == .current) // hedef bölüm artık erişilebilir → .current
    }

    @Test func yuklemePenceresindeGelenUnlockSinyaliYutulmaz() async {
        // self-review H3 (CONFIRMED): load()'un recompute'u (canlı entitlement okur) ile loadState=.loaded arası
        // favorites-await penceresinde gelen sinyal eskiden `guard loadState==.loaded` ile YUTULUP CTA bayat
        // kalıyordu. Guard artık `ctaTarget != nil` → o pencerede işlenir, CTA yeniden türetilir (fail-closed).
        let spy = lockedSeriesCatalog()
        let entitlement = FakeEntitlements()
        let changes = ManualEntitlementChanges()
        let favorites = GateFavorites()
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 3, completed: false))
        let model = DiziDetayModel(
            seriesID: seriesID,
            source: .kesfet,
            catalog: spy,
            history: history,
            favorites: favorites,
            entitlement: entitlement,
            analytics: MockAnalytics(),
            delegate: nil,
            entitlementChanges: changes,
            now: { now }
        )

        model.onAppear()
        await favorites.waitUntilEntered() // load favorites-await'inde askıda: ctaTarget kuruldu, loadState .loading

        #expect(model.ctaLocked) // Bölüm 3 kilitli (entitlement henüz vermedi)

        // Yükleme PENCERESİNDE unlock + sinyal (eski bug'ın erişilebilir hali: cold-start/deep-link broadcast).
        entitlement.grant(EpisodeID("srs_abc123_e3"))
        changes.emit()
        for _ in 0 ..< 1000 where model.ctaLocked {
            await Task.yield() // gözlemci re-derive edene dek (sınırlı — asılmaz)
        }

        #expect(!model.ctaLocked) // pencere içinde işlendi → kilit kalktı (eski kod: yutulur, kilitli kalırdı)

        favorites.release()
        await model.pendingWork()
        #expect(!model.ctaLocked) // load tamamlandıktan sonra da kilitsiz (load son yazımı access'i ezmez)
    }
}
