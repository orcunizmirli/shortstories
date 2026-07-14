import AppFoundation
import ContentKit
import Foundation

/// 3–5 player instance'lık havuz (04 §3, 03 §7.1 — kanonik actor). Player'lar
/// hücrelere değil feed indeksine bağlanır; hücreler yeniden kullanılırken
/// player'lar havuzda yaşar ve ASLA deallocate edilmez (04 §3.3 kural 1).
///
/// Public yüzey yalnız kompozisyon kökünün gördüğü `init`'tir (04 §2.4).
/// Operasyonlar (`activate`/`prepareNext`/`recycle`/`acquire`/`Lease`/
/// `advanceWindow`/`drain`) PlayerKit-internal'dır — feed VC aynı modülde yaşar (C2).
public actor PlayerPool {
    /// Slot kiralama makbuzu (PlayerKit-internal — 04 §3.3): engine referansı
    /// modül dışına sızmaz.
    struct Lease: Sendable {
        let engine: PlaybackEngine
        let episodeID: EpisodeID
        let slot: Int
    }

    private struct Slot {
        let engine: PlaybackEngine
        var episodeID: EpisodeID?
        var feedIndex: Int?
        var role: SlotRole
        /// Claim işareti: authorize uçuşu boyunca slot planlayıcıya kapalıdır.
        var isAuthorizing = false
    }

    private var slots: [Slot]
    private var activeSlot: Int?
    private var activeFeedIndex: Int?
    /// Uçuştaki claim'ler (dedup): aynı bölümün ikinci acquire'ı çözülmeyi bekler.
    private var authorizingEpisodes: Set<EpisodeID> = []
    private var claimWaiters: [EpisodeID: [CheckedContinuation<Void, Never>]] = [:]
    /// Epoch korkuluğu: `drain` artırır; uçuştaki iş dönüşte değişim görürse iptal olur.
    private var drainEpoch: UInt64 = 0
    private let authorization: PlaybackAuthorizationProvider
    private let entitlements: any EntitlementChecking
    private let network: any NetworkConditionProviding
    private let preferences: any PlaybackPreferencesProviding
    private let logger: any Logging

    /// Kompozisyon kökü (ShortSeriesApp) init'i: AVFoundation backend'iyle kurulur.
    /// `Dependencies` konteynerine KONMAZ; `PlayerFeedView`'a init-injection ile verilir
    /// (04 §2.4 kural 2, 03 §5.1). Havuz bütçesi kanonik 3–5 (04 §1); portlar: `playback`
    /// imzalı URL, `entitlements` kilit erişimi (03 §4 R8), `network` ağ koşulu (SS-026,
    /// bitrate tavanı 04 §6.3), `preferences` veri tasarrufu (04 §5.3), `logger` loglama.
    public init(
        size: Int = 3,
        playback: any PlaybackServicing,
        entitlements: any EntitlementChecking,
        network: any NetworkConditionProviding,
        preferences: any PlaybackPreferencesProviding,
        logger: any Logging
    ) {
        self.init(
            size: size,
            backendFactory: { AVPlayerBackend() },
            playback: playback,
            entitlements: entitlements,
            network: network,
            preferences: preferences,
            logger: logger
        )
    }

    /// Test dikişi: backend fabrikası enjekte edilir; birim testleri gerçek medya
    /// olmadan sahte backend'lerle koşar.
    init(
        size: Int,
        backendFactory: @Sendable () -> any VideoPlaying,
        playback: any PlaybackServicing,
        entitlements: any EntitlementChecking,
        network: any NetworkConditionProviding,
        preferences: any PlaybackPreferencesProviding,
        logger: any Logging
    ) {
        precondition((3 ... 5).contains(size), "Havuz bütçesi 3–5 (kanon — 04 §14 T14)")
        let provider = PlaybackAuthorizationProvider(service: playback)
        authorization = provider
        self.entitlements = entitlements
        self.network = network
        self.preferences = preferences
        self.logger = logger
        let freshURL: @Sendable (EpisodeID) async throws -> URL = { episodeID in
            try await provider.freshAuthorization(for: episodeID).playbackURL
        }
        slots = (0 ..< size).map { _ in
            Slot(
                engine: PlaybackEngine(backend: backendFactory(), freshURLProvider: freshURL),
                episodeID: nil,
                feedIndex: nil,
                role: .idle
            )
        }
    }

    // MARK: - Operasyon yüzeyi (PlayerKit-internal — 04 §2.4)

    /// Bölümü aktifleştirir: warm slot varsa aynı engine'le (cold start yok — 04 §3.3),
    /// yoksa en uzak slot geri alınıp yüklenir. Önceki aktif demote edilir (1 sn buffer),
    /// yeni aktif otomatik buffer'a geçer ve beklemeden oynatılır (04 §4.1).
    /// Kilitli ve entitlement'sız bölüm OYNATILMAZ (04 §9.1); `AppError.content(.episodeLocked)`
    /// fırlatılır — UnlockSheet akışını çağıran katman (feed VC → Coordinator) tetikler.
    func activate(
        _ episode: Episode,
        atFeedIndex feedIndex: Int,
        resumePosition: Double? = nil
    ) async throws -> PlaybackHandle {
        guard await isPlayable(episode) else {
            throw AppError.content(.episodeLocked(EpisodeLockDetails(
                unlockPrice: episode.access.unlockPrice,
                adUnlockEligible: episode.access.adUnlockEligible,
                wallet: nil
            )))
        }
        let epoch = drainEpoch
        let lease = try await acquire(
            for: episode,
            atFeedIndex: feedIndex,
            role: .active,
            resumePosition: resumePosition
        )
        // Epoch korkuluğu: askıdayken drain geldiyse yazma/başlatma yok — temiz iptal.
        guard drainEpoch == epoch else { throw CancellationError() }
        await demotePreviousActive(except: lease.slot)
        activeSlot = lease.slot
        activeFeedIndex = feedIndex
        // Warm-hit'te buffer yerinde otomatik moda çekilir (04 §4.1 promoteToActive).
        await lease.engine.applyBufferPolicy(.active)
        await lease.engine.play()
        return PlaybackHandle(episodeID: lease.episodeID, engine: lease.engine)
    }

    /// Komşu bölümü ısındırır: item yüklü + paused + 1 sn buffer (04 §3.2).
    /// Kilitli ve entitlement'sız bölüm ISINDIRILMAZ (04 §9.1 kural 4) — boşa
    /// authorize isteği ve 403 gürültüsü önlenir.
    func prepareNext(_ episode: Episode, atFeedIndex feedIndex: Int) async {
        guard await isPlayable(episode) else {
            logger.debug("PlayerPool: kilitli bölüm ısındırılmadı episodeID=\(episode.id.rawValue)")
            return
        }
        do {
            _ = try await acquire(for: episode, atFeedIndex: feedIndex, role: .warm)
        } catch is CancellationError {
            // İptal hata değildir (03 §7.3): slot temiz bırakıldı, gürültü yok.
            logger.debug("PlayerPool: prefetch iptal edildi episodeID=\(episode.id.rawValue)")
        } catch {
            logger.error("PlayerPool: prefetch hazırlığı başarısız episodeID=\(episode.id.rawValue)")
        }
    }

    /// Pencere dışına düşen slot'ları boşaltır (03 §7.1); item gider, player kalır.
    func recycle(keeping window: ClosedRange<Int>) async {
        for index in slots.indices where index != activeSlot {
            guard let feedIndex = slots[index].feedIndex, !window.contains(feedIndex) else { continue }
            await clearSlot(index)
        }
    }

    /// Aktif bölüm değişti (kaydırma yerleşti): rolleri ve pencereyi günceller.
    /// Feed VC dilimi (SS-044) bu noktadan sürer; prefetch tetiği PrefetchController'dadır.
    func advanceWindow(activeEpisodeID: EpisodeID, direction _: ScrollDirection) async {
        guard let newActive = slots.firstIndex(where: { $0.episodeID == activeEpisodeID }) else {
            logger.debug("PlayerPool: advanceWindow slot bulunamadı episodeID=\(activeEpisodeID.rawValue)")
            return
        }
        await demotePreviousActive(except: newActive)
        slots[newActive].role = .active
        activeSlot = newActive
        activeFeedIndex = slots[newActive].feedIndex
        await slots[newActive].engine.applyBufferPolicy(.active)
    }

    /// Feed'den çıkışta / bellek uyarısında: item'lar bırakılır, player'lar KORUNUR
    /// (04 §3.3). `keepPlayers` sözleşme gereği taşınır; player'ları düşürme kararı
    /// bu dilimde YOKTUR (bellek uyarısında havuzu 3'e küçültme SS-044 dilimindedir).
    func drain(keepPlayers _: Bool = true) async {
        // Epoch korkuluğu: uçuştaki acquire/activate dönüşte iptalle temiz çıkar.
        drainEpoch &+= 1
        for index in slots.indices {
            await clearSlot(index)
        }
        activeSlot = nil
        activeFeedIndex = nil
    }

    // MARK: - Test/debug görünürlüğü

    var slotCount: Int {
        slots.count
    }

    func snapshotEpisodeIDs() -> [EpisodeID?] {
        slots.map(\.episodeID)
    }

    func snapshotRoles() -> [SlotRole] {
        slots.map(\.role)
    }

    func snapshotEngineStates() async -> [PlayerEngineState] {
        var states: [PlayerEngineState] = []
        for slot in slots {
            await states.append(slot.engine.currentState())
        }
        return states
    }

    /// Test dikişi: acquire girişini gözlemler — yarış testleri claim/authorize
    /// penceresini deterministik kurmak için kullanır. Üretimde nil kalır.
    private var acquireObserver: (@Sendable (EpisodeID) -> Void)?

    func setAcquireObserver(_ observer: (@Sendable (EpisodeID) -> Void)?) {
        acquireObserver = observer
    }

    // MARK: - Yardımcılar

    /// Anlık ağ koşulu + veri tasarrufu tercihine göre bitrate tavanı (04 §6.3):
    /// hücresel+tasarruf = 480p, hücresel = 720p, Wi-Fi = nil (tavansız, ABR).
    private func currentPeakBitRateCap() async -> Double? {
        let condition = await network.currentCondition()
        let isDataSaverEnabled = await preferences.isDataSaverEnabled()
        return BitrateCapPolicy.peakBitRateCap(network: condition, isDataSaverEnabled: isDataSaverEnabled)
    }

    private func isPlayable(_ episode: Episode) async -> Bool {
        if episode.access.isPlayableWithoutUnlock {
            return true
        }
        return await entitlements.hasAccess(to: episode.id)
    }

    private func demotePreviousActive(except keptSlot: Int) async {
        guard let previous = activeSlot, previous != keptSlot,
              slots[previous].role == .active
        else { return }
        slots[previous].role = .warm
        await slots[previous].engine.pause()
        await slots[previous].engine.applyBufferPolicy(.idle)
    }

    private func clearSlot(_ index: Int) async {
        await slots[index].engine.reset()
        slots[index].episodeID = nil
        slots[index].feedIndex = nil
        slots[index].role = .idle
    }
}

// MARK: - Kiralama mekaniği (claim-önce-await)

extension PlayerPool {
    /// Bölüm için player kirala. Bölüm zaten bir slot'ta hazırsa aynı player döner.
    ///
    /// Claim-önce-await: rezervasyon authorize suspension'ından ÖNCE senkron yazılır —
    /// reentrancy altında farklı bölümler aynı slotu seçemez, aynı bölüm dedup'a takılır.
    /// Başarısızlık/iptalde rezervasyon senkron temizlenir; drain/recycle araya girdiyse
    /// iptalle temiz çıkılır.
    func acquire(
        for episode: Episode,
        atFeedIndex feedIndex: Int,
        role: SlotRole,
        resumePosition: Double? = nil
    ) async throws -> Lease {
        acquireObserver?(episode.id)
        // Dedup: aynı bölümün uçuştaki claim'i çözülene dek bekle.
        while authorizingEpisodes.contains(episode.id) {
            await withCheckedContinuation { continuation in
                claimWaiters[episode.id, default: []].append(continuation)
            }
        }
        try Task.checkCancellation()
        if let existing = slots.firstIndex(where: { $0.episodeID == episode.id }) {
            return try await reuseWarmSlot(
                existing,
                episode: episode,
                atFeedIndex: feedIndex,
                role: role,
                resumePosition: resumePosition
            )
        }

        guard let slotIndex = PoolWindowPlanner.reclaimableSlot(
            feedIndexes: slots.map(\.feedIndex),
            activeSlot: activeSlot,
            activeFeedIndex: activeFeedIndex,
            excluding: Set(slots.indices.filter { slots[$0].isAuthorizing })
        ) else {
            throw AppError.unexpected(underlying: "PlayerPool: geri alınabilir slot yok")
        }

        claimSlot(slotIndex, for: episode, atFeedIndex: feedIndex, role: role)
        let epoch = drainEpoch
        defer { resolveClaim(at: slotIndex, for: episode.id) }
        do {
            let auth = try await authorization.authorization(for: episode.id)
            // İptal gözlemi (03 §7.3): iptal edilen prefetch slot'u temiz bırakır.
            try Task.checkCancellation()
            try ensureClaimIntact(at: slotIndex, for: episode.id, epoch: epoch)
            // Bitrate tavanı yüklemeden ÖNCE uygulanır (04 §6.3).
            await slots[slotIndex].engine.setPeakBitRateCap(currentPeakBitRateCap())
            await slots[slotIndex].engine.prepare(
                episodeID: episode.id,
                url: auth.playbackURL,
                bufferPolicy: role == .active ? .active : .idle,
                resumePosition: resumePosition
            )
            try ensureClaimIntact(at: slotIndex, for: episode.id, epoch: epoch)
            return Lease(engine: slots[slotIndex].engine, episodeID: episode.id, slot: slotIndex)
        } catch {
            releaseClaimIfOwned(at: slotIndex, for: episode.id)
            throw error
        }
    }

    /// Warm-hit yolu: aynı engine yeniden kullanılır (cold start yok — 04 §3.3).
    /// - İmzalı URL bayatsa (04 §6.4 kural 4) taze authorize + yeniden hazırlama —
    ///   süresi geçmiş yetkiyle oynatma BAŞLATILMAZ.
    /// - Slot sağlığı: engine `.failed` ise auth taze olsa bile taze yetkiyle YENİDEN
    ///   hazırlanır — ölü engine'e lease dönmez, "Tekrar dene" gerçekten dener.
    /// - `resumePosition` verilmişse hazır item'da o konuma seek edilir (04 §12.2).
    private func reuseWarmSlot(
        _ slotIndex: Int,
        episode: Episode,
        atFeedIndex feedIndex: Int,
        role: SlotRole,
        resumePosition: Double?
    ) async throws -> Lease {
        slots[slotIndex].role = role
        slots[slotIndex].feedIndex = feedIndex
        let engine = slots[slotIndex].engine
        // Aktivasyon anında ağ koşulu değişmiş olabilir; tavan yeniden uygulanır (04 §6.3).
        await engine.setPeakBitRateCap(currentPeakBitRateCap())
        var engineFailed = false
        if case .failed = await engine.currentState() {
            engineFailed = true
        }
        if !engineFailed, await authorization.hasUsableAuthorization(for: episode.id) {
            if let resumePosition {
                await engine.seek(toSeconds: resumePosition)
            }
        } else {
            let fresh = try await authorization.freshAuthorization(for: episode.id)
            await engine.prepare(
                episodeID: episode.id,
                url: fresh.playbackURL,
                bufferPolicy: role == .active ? .active : .idle,
                resumePosition: resumePosition
            )
        }
        return Lease(engine: engine, episodeID: episode.id, slot: slotIndex)
    }

    /// Rezervasyonu SENKRON yazar: authorize askısı boyunca slot planlayıcıya kapalı.
    private func claimSlot(_ slotIndex: Int, for episode: Episode, atFeedIndex feedIndex: Int, role: SlotRole) {
        slots[slotIndex].episodeID = episode.id
        slots[slotIndex].feedIndex = feedIndex
        slots[slotIndex].role = role
        slots[slotIndex].isAuthorizing = true
        authorizingEpisodes.insert(episode.id)
    }

    /// Claim çözüldü: işaret düşer, aynı bölümü bekleyen acquire'lar devam eder.
    private func resolveClaim(at slotIndex: Int, for episodeID: EpisodeID) {
        slots[slotIndex].isAuthorizing = false
        authorizingEpisodes.remove(episodeID)
        for waiter in claimWaiters.removeValue(forKey: episodeID) ?? [] {
            waiter.resume()
        }
    }

    /// Epoch/claim korkuluğu: araya drain (epoch artar) ya da recycle (claim'i
    /// temizler) girdiyse iptalle temiz çıkılır — yazma/başlatma yapılmaz.
    private func ensureClaimIntact(at slotIndex: Int, for episodeID: EpisodeID, epoch: UInt64) throws {
        guard drainEpoch == epoch, slots[slotIndex].episodeID == episodeID else {
            throw CancellationError()
        }
    }

    /// Başarısız/iptal edilen claim'in rezervasyonunu senkron temizler — claim hâlâ
    /// bizimse. (Drain/recycle temizlediyse dokunmaz: slot başka akışın kontrolünde.)
    private func releaseClaimIfOwned(at slotIndex: Int, for episodeID: EpisodeID) {
        guard slots[slotIndex].isAuthorizing, slots[slotIndex].episodeID == episodeID else { return }
        slots[slotIndex].episodeID = nil
        slots[slotIndex].feedIndex = nil
        slots[slotIndex].role = .idle
    }
}

// MARK: - EpisodeWarming

extension PlayerPool: EpisodeWarming {
    /// PrefetchController'ın havuza dar köprüsü: warm = prepareNext.
    func warm(_ episode: Episode, atFeedIndex feedIndex: Int) async {
        await prepareNext(episode, atFeedIndex: feedIndex)
    }
}
