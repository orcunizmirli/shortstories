import AppFoundation
import ContentKit
import Foundation
import Observation

/// DiziDetay ekran modeli (SS-080/081/083). @Observable/@MainActor; SwiftUI View ince kalır.
/// Kapak/özet/etiketler/bölüm ızgarası; "İzlemeye Başla/Devam Et" CTA (izleme geçmişinden
/// metin+hedef+pozisyon); release schedule; listeye ekle/favori; paylaş universal link. Kilitli
/// bölüme dokununca UnlockSheet intent (delegate). WalletKit/PlayerKit import EDİLMEZ.
@MainActor
@Observable
public final class DiziDetayModel {
    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        case error
        case offline
        /// Geçersiz/kaldırılmış içerik (02 §4.4 boş durum: "Bu dizi artık yayında değil").
        case removed
    }

    // MARK: - Durum (Observable)

    public private(set) var loadState: LoadState = .loading
    public private(set) var series: Series?
    public private(set) var episodes: [Episode] = []
    public private(set) var isFavorite = false
    public private(set) var ctaTarget: ContinueWatchingTarget?
    /// CTA hedef bölümü kilitli mi (Devam Et · Bölüm N 🔒; dokununca UnlockSheet, §4.4).
    public private(set) var ctaLocked = false
    public private(set) var releaseInfo: ReleaseScheduleInfo?
    public private(set) var episodeBlocks: [EpisodeBlock] = []
    public private(set) var synopsisExpanded = false
    public private(set) var isLoadingEpisodes = false

    // MARK: - Bağımlılıklar

    private let seriesID: SeriesID
    private let source: DiziDetaySource
    private let catalog: any CatalogServicing
    private let history: any WatchHistoryReading
    private let favorites: any FavoritesGateway
    private let entitlement: any EntitlementChecking
    /// Entitlement DEĞİŞİM sinyali (bug-hunt #2): açıkken unlock/VIP olursa erişimi yeniden türetir. nil =
    /// gözlem yok (test/eski çağıran). App WalletStore.entitlementUpdates'ı void'e map ederek bağlar.
    private let entitlementChanges: (any EntitlementChangeObserving)?
    private let analytics: any AnalyticsTracking
    private let now: @Sendable () -> Date
    private weak var delegate: (any DiziDetayDelegate)?

    private var accessibleEpisodeIDs: Set<EpisodeID> = []
    /// recomputeAccess kuşak jetonu: load-recompute ile #2 gözlemcisi eşzamanlı çağırırsa son-başlayan kazanır.
    private var accessRecomputeGeneration = 0
    private var hasHistory = false
    private var episodesCursor: String?
    /// onAppear re-entrancy guard: ilk görünümde bir kez load(); tekrar görünümde state EZİLMESİN.
    private var appeared = false
    private var loadTask: Task<Void, Never>?
    /// load() uçuş guard'ı (#8): View'in .error/.offline "Tekrar Dene" butonu load()'u DOĞRUDAN çağırır →
    /// hızlı çift-dokunma iki eşzamanlı load() başlatıp episodes/cursor/erişim state'ini yarıştırır.
    private var isLoadingDetail = false
    /// toggleFavorite in-flight guard: örtüşen toggle'lar sunucudan sapmasın.
    private var isTogglingFavorite = false
    /// #2 gözlem görevi; deinit'te iptal. `nonisolated(unsafe)`: yalnız MainActor'da yazılır + deinit'te iptal → güvenli.
    private nonisolated(unsafe) var entitlementObserveTask: Task<Void, Never>?

    public init(
        seriesID: SeriesID,
        source: DiziDetaySource,
        catalog: any CatalogServicing,
        history: any WatchHistoryReading,
        favorites: any FavoritesGateway,
        entitlement: any EntitlementChecking,
        analytics: any AnalyticsTracking,
        delegate: (any DiziDetayDelegate)?,
        entitlementChanges: (any EntitlementChangeObserving)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.seriesID = seriesID
        self.source = source
        self.catalog = catalog
        self.history = history
        self.favorites = favorites
        self.entitlement = entitlement
        self.entitlementChanges = entitlementChanges
        self.analytics = analytics
        self.delegate = delegate
        self.now = now
    }

    deinit {
        entitlementObserveTask?.cancel()
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        guard !appeared else { return }
        appeared = true
        loadTask = Task { await load() }
        startObservingEntitlementChanges()
    }

    /// #2: unlock/VIP değişiminde erişim kümesi + CTA'yı yeniden türet — kullanıcı ödediği bölümü bu ekrandan
    /// oynayabilsin (aksi halde CTA 🔒 kalıp sahip olunan bölüm için UnlockSheet yeniden açılıyordu). Coordinator
    /// wiring GEREKMEZ (model kendisi gözlemler); hafif re-derive (progress ağ-fetch'i yok).
    private func startObservingEntitlementChanges() {
        guard let entitlementChanges else { return }
        entitlementObserveTask = Task { [weak self] in
            for await _ in entitlementChanges.entitlementChanges() {
                // `ctaTarget != nil` = içerik türetildi. `loadState == .loaded` YERİNE (self-review yarışı:
                // recompute ile loadState=.loaded arası favorites-await penceresinde sinyal yutulup CTA bayat kalırdı).
                guard let self, ctaTarget != nil else { continue }
                await recomputeAccess()
            }
        }
    }

    /// Testler için: askıdaki ilk yükleme görevini bekler (deterministik).
    func pendingWork() async {
        await loadTask?.value
    }

    public func load() async {
        guard !isLoadingDetail else { return } // #8: çift "Tekrar Dene" dokunması eşzamanlı load'u yarıştırmasın
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        loadState = .loading
        do {
            async let detailTask = catalog.seriesDetail(id: seriesID)
            async let episodesTask = catalog.episodes(seriesId: seriesID, cursor: nil)
            let detail = try await detailTask
            let page = try await episodesTask
            series = detail
            episodes = page.items
            episodesCursor = page.items.isEmpty ? nil : page.nextCursor // #4 simetrik: boş+cursor sonsuz sayfalama önle
            releaseInfo = ReleaseScheduleInfo.resolve(series: detail)
            episodeBlocks = EpisodeBlocks.make(episodeCount: detail.episodeCount)
            await recompute()
            isFavorite = await favorites.isFavorite(seriesID)
            loadState = .loaded
            trackDetailView(detail)
        } catch let error as AppError {
            handleLoadError(error)
        } catch {
            loadState = .error
        }
    }

    private func handleLoadError(_ error: AppError) {
        switch error {
        case .content(.notFound), .content(.regionBlocked):
            loadState = .removed
        case .network(.offline):
            loadState = .offline
        default:
            loadState = .error
        }
    }

    /// Geçmiş → CTA hedefi + erişilebilirlik kümesi + CTA kilidi (tümü tekrar; yeni sayfa yüklenince de çağrılır).
    private func recompute() async {
        guard let series else { return }
        let progress = await history.latestProgress(forSeries: seriesID)
        hasHistory = progress != nil
        // İlerleme bölümü ilk sayfada değilse CTA'yı doğru türetmek için o sayfayı çek (aksi halde resolve()
        // baştan-başlat'a düşer, PlayerFeed yanlış bölüme girer §4.4). BEST-EFFORT: derin-sayfa ağ hatasında
        // load'u BOZMA (hata yüzdürmek canlı diziyi `.removed` dead-end'ine düşürüyordu) — CTA .start (kabul-LOW).
        await ensureProgressEpisodeLoaded(progress)
        let target = ContinueWatchingTarget.resolve(series: series, episodes: episodes, progress: progress)
        // CTA hedef bölümü (izlenen+1) sonraki cursor sayfasında olabilir; kilit türetimi + primaryCTA hedef
        // Episode'unu YÜKLÜ ister → çek (aksi halde kilitli hedef UnlockSheet atlanarak oynardı — paywall bypass).
        await ensureEpisodeLoaded(number: target.episodeNumber)
        ctaTarget = target
        await recomputeAccess()
    }

    /// İzleme ilerleme bölümü yüklü değilse bulunana/sayfalar bitene kadar ileri sayfala (`WatchProgress` yalnız
    /// `episodeId` taşır → Episode'u lazım). Tekrarlanan/ilerlemeyen cursor'da durur (bayat/kaldırılmış: döngü koruması).
    private func ensureProgressEpisodeLoaded(_ progress: WatchProgress?) async {
        guard let progress else { return }
        var visitedCursors: Set<String> = []
        while !episodes.contains(where: { $0.id == progress.episodeId }) {
            // Sayfa BİTTİ (cursor nil) ya da ilerlemeyen cursor → bölüm gerçekten yok (bayat/kaldırılmış) → legit çık.
            guard let cursor = episodesCursor, !visitedCursors.contains(cursor) else { return }
            visitedCursors.insert(cursor)
            // BEST-EFFORT (self-review): derin-sayfa hatasını YÜZDÜRMEK canlı diziyi `.removed`/`.error` dead-end'ine
            // düşürüyordu → `try?` ile yut, CTA .start'a düşer (kabul-LOW; doğru fix episodeId-resume → PREP).
            guard let page = try? await catalog.episodes(seriesId: seriesID, cursor: cursor) else { return }
            appendUniqueEpisodes(page.items)
            episodesCursor = page.items.isEmpty ? nil : page.nextCursor // #4 simetrik (boş+cursor sonsuz sayfalama önle)
        }
    }

    /// CTA hedef bölüm Episode'u yüklü değilse bulunana/sayfalar bitene kadar ileri sayfala (ensureProgress
    /// EpisodeLoaded yalnız İZLENENİ garanti eder; resume hedefi izlenen+1 sonraki sayfada olabilir).
    private func ensureEpisodeLoaded(number: Int) async {
        var visitedCursors: Set<String> = []
        while !episodes.contains(where: { $0.index == number }) {
            guard let cursor = episodesCursor, !visitedCursors.contains(cursor) else { return }
            visitedCursors.insert(cursor)
            guard let page = try? await catalog.episodes(seriesId: seriesID, cursor: cursor) else { return }
            appendUniqueEpisodes(page.items)
            episodesCursor = page.nextCursor
            // Sayfa index'leri artan; maks index hedefi GEÇTİYSE hedef ya bu sayfada geldi ya da index boşluğu
            // (kaldırılmış bölüm / releasedEpisodeCount aşımı) → sonrakilerde YOK, tam-taramayı bırak (audit LOW).
            if let maxIndex = page.items.map(\.index).max(), maxIndex >= number {
                return
            }
        }
    }

    /// Sayfa-sınırı örtüşmesi: aynı EpisodeID iki kez `episodes`'a girmesin (ForEach id çakışması,
    /// bozuk diffing) — AramaModel.loadMore ile simetrik dedup (audit MEDIUM).
    private func appendUniqueEpisodes(_ items: [Episode]) {
        let existing = Set(episodes.map(\.id))
        episodes += items.filter { !existing.contains($0.id) }
    }

    // MARK: - Bölüm ızgarası hücre durumu (View bunu çizer)

    public func cellState(for episode: Episode) -> EpisodeCellState {
        let isCurrent = hasHistory && ctaTarget?.episodeNumber == episode.index
        let isWatched = hasHistory && (ctaTarget.map { episode.index < $0.episodeNumber } ?? false)
        let accessible = isEpisodeAccessible(episode)
        return EpisodeCellState.resolve(
            episode: episode,
            isWatched: isWatched,
            isCurrent: isCurrent,
            isAccessible: accessible,
            now: now()
        )
    }

    private func isEpisodeAccessible(_ episode: Episode) -> Bool {
        accessibleEpisodeIDs.contains(episode.id) || episode.access.isPlayableWithoutUnlock
    }

    // MARK: - Aksiyonlar

    /// Birincil CTA (§4.4): açık ise `PlayerFeed` (bağlamsal, pozisyonla); kilitliyse UnlockSheet.
    public func primaryCTA() {
        guard let series, let target = ctaTarget else { return }
        analytics.track(
            "series_cta_tapped",
            parameters: [
                "type": .string(target.kind == .start ? "start" : "continue"),
                "episode_number": .int(target.episodeNumber)
            ]
        )
        if ctaLocked, let episode = episodes.first(where: { $0.index == target.episodeNumber }) {
            // Kilitli VE hedef Episode yüklü → UnlockSheet intent (coin fiyatı vb. buradan).
            delegate?.diziDetayRequestsUnlock(intent(for: episode, series: series))
        } else {
            // Açık hedef VEYA hedef Episode yüklenemedi (ağ hatası, ctaLocked güvenli-taraf true): server-
            // otoriter oynatma dene — entitled ise oynar, kilitliyse feed authorize REDDEDER → paywall geç
            // gösterilir (backstop). Sessiz DEAD-BUTTON değil (self-review: entitled kullanıcıyı kilitlemesin).
            delegate?.diziDetayStartWatching(
                seriesID: seriesID,
                episodeNumber: target.episodeNumber,
                startPositionSec: target.startPositionSec
            )
        }
    }

    /// Izgara hücresi (§4.4): açık bölüm → oynat; kilitli → UnlockSheet; yayınlanmamış → no-op.
    public func selectEpisode(_ episode: Episode) {
        guard let series, episode.isPublished(at: now()) else { return }
        let accessible = isEpisodeAccessible(episode)
        analytics.track(
            "episode_grid_tapped",
            parameters: ["episode_number": .int(episode.index), "locked": .bool(!accessible)]
        )
        if accessible {
            delegate?.diziDetayStartWatching(
                seriesID: seriesID,
                episodeNumber: episode.index,
                startPositionSec: resumePosition(for: episode)
            )
        } else {
            delegate?.diziDetayRequestsUnlock(intent(for: episode, series: series))
        }
    }

    /// Listeye ekle/favori toggle (§4.4/§4.10). Optimistik; server hatasında geri alınır.
    /// In-flight guard: bir toggle sunucuda askıdayken ikinci dokunuş yok sayılır (örtüşen
    /// yazımlar sunucudan sapmasın, bayat rollback yeniyi ezmesin). Analitik `favorite_add/
    /// remove` event'i sunucu ONAYINDA atılır (08 §3.3): optimistik-öncesi değil, başarıda.
    public func toggleFavorite() async {
        guard series != nil, !isTogglingFavorite else { return }
        isTogglingFavorite = true
        defer { isTogglingFavorite = false }
        let target = !isFavorite
        isFavorite = target
        do {
            try await favorites.setFavorite(target, seriesID: seriesID)
            analytics.track(
                target ? "favorite_add" : "favorite_remove",
                parameters: ["series_id": .string(seriesID.rawValue), "source": .string("dizi_detay")]
            )
        } catch {
            isFavorite = !target
        }
    }

    /// Paylaş (§4.4, §8.1.1): universal link (shortseries.app) → share sheet.
    public func share() {
        analytics.track(
            "share_tap",
            parameters: ["series_id": .string(seriesID.rawValue), "source": .string(source.rawValue)]
        )
        delegate?.diziDetayShare(DeepLinkResolver.shareLink(forSeries: seriesID))
    }

    /// Etiket çipi → `Kesfet` tür filtresi (§4.4).
    public func selectTag(_ tag: Tag) {
        analytics.track("tag_tapped", parameters: ["tag_id": .string(tag.id)])
        delegate?.diziDetayRequestsDiscover(genre: tag.id)
    }

    /// Kaldırılmış içerik boş durumu CTA'sı → `Kesfet` köküne dön (02 §4.4).
    public func openDiscover() {
        delegate?.diziDetayRequestsDiscoverRoot()
    }

    public func toggleSynopsis() {
        synopsisExpanded.toggle()
    }

    /// Bölüm ızgarası sayfalama (100+ bölüm; cursor, 05 §7.1).
    public func loadMoreEpisodes() async {
        guard let cursor = episodesCursor, !isLoadingEpisodes else { return }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        guard let page = try? await catalog.episodes(seriesId: seriesID, cursor: cursor) else { return }
        appendUniqueEpisodes(page.items)
        // #4: boş items + non-nil cursor (sunucu/proxy bug) → cursor nil'lenmezse her scroll-sonu loadMore'u
        // SONSUZ yeniden tetikler (AramaModel.loadMore ile simetrik guard).
        episodesCursor = page.items.isEmpty ? nil : page.nextCursor
        await recompute()
    }
}

// MARK: - İç yardımcılar (type_body_length: same-file extension gövdeye sayılmaz)

private extension DiziDetayModel {
    /// Erişilebilirlik kümesi + CTA kilidini entitlement'tan yeniden türetir. recompute alt-adımı; #2
    /// gözlemcisi de unlock/VIP sonrası çağırır (hafif — progress ağ-fetch'i yok). `ctaTarget` hazır olmalı.
    func recomputeAccess() async {
        accessRecomputeGeneration += 1
        let generation = accessRecomputeGeneration
        var accessible: Set<EpisodeID> = []
        for episode in episodes {
            if episode.access.isPlayableWithoutUnlock {
                accessible.insert(episode.id)
            } else if await entitlement.hasAccess(to: episode.id) {
                accessible.insert(episode.id)
            }
        }
        // Sonradan başlayan recomputeAccess (daha taze entitlement) araya girdiyse bu bayat commit'i düşür.
        guard generation == accessRecomputeGeneration else { return }
        accessibleEpisodeIDs = accessible

        guard let target = ctaTarget else { return }
        if let episode = episodes.first(where: { $0.index == target.episodeNumber }) {
            ctaLocked = !accessible.contains(episode.id)
        } else {
            // Hedef bölüm sayfalar tükenmesine rağmen yüklenemedi (ör. ağ hatası) → çözülemeyen kilit
            // KİLİTLİ varsayılır (güvenli taraf, 05 §12 kural 4); erişilemeyen bölüm oynatmaya gitmesin.
            ctaLocked = true
        }
    }

    func resumePosition(for episode: Episode) -> Double {
        guard let target = ctaTarget, target.episodeNumber == episode.index else { return 0 }
        return target.startPositionSec
    }

    func intent(for episode: Episode, series: Series) -> LockedEpisodeIntent {
        LockedEpisodeIntent(
            seriesID: seriesID,
            episodeID: episode.id,
            seriesTitle: series.title,
            episodeNumber: episode.index,
            unlockPrice: episode.access.unlockPrice
        )
    }

    func trackDetailView(_ series: Series) {
        analytics.track(
            "series_detail_view",
            parameters: [
                "series_id": .string(seriesID.rawValue),
                "source": .string(source.rawValue),
                "free_episode_count": .int(series.freeEpisodeCount),
                "total_episode_count": .int(series.episodeCount)
            ]
        )
    }
}
