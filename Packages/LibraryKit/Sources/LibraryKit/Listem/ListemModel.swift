import AppFoundation
import Foundation
import Observation

/// Bir segmentin yükleme durumu (02 §3 sözleşmesi). Listem lokal veriden beslenir → pratikte
/// anlık; hata durumu yoktur (lokal her zaman gösterilir, senkron sessizce ertelenir, §4.12).
public enum SegmentLoadState: Equatable, Sendable {
    case loading
    case loaded
    case empty
}

/// `Listem` ekran modeli (SS-120). @Observable/@MainActor; SwiftUI View ince kalır. Segmentli
/// yapı (Favoriler / Devam Et; İndirilenler F3-flag), boş durumlar, düzenleme modu çoklu silme.
/// Favori verisi `FavoritesService`, "devam et" verisi `ContinueWatchingService` TEK KAYNAK'tan
/// gelir; katalog metadata `LibraryCatalogReading` ile JOIN edilir. Player/DiziDetay import
/// EDİLMEZ — navigasyon `ListemDelegate` niyetleriyle (App bağlar).
@MainActor
@Observable
public final class ListemModel {
    // MARK: - Durum (Observable)

    public private(set) var segment: MyListSegment
    public let visibleSegments: [MyListSegment]

    public private(set) var favoritesState: SegmentLoadState = .loading
    public private(set) var continueState: SegmentLoadState = .loading
    public private(set) var favorites: [FavoriteItem] = []
    public private(set) var continueItems: [ContinueWatchingItem] = []

    /// Favoriler düzenleme modu (çoklu seçim + kaldır, §4.12).
    public private(set) var isEditing = false
    public private(set) var selectedForRemoval: Set<SeriesID> = []

    // MARK: - Bağımlılıklar

    private let favoritesService: FavoritesService
    private let continueWatchingService: ContinueWatchingService
    private let catalog: any LibraryCatalogReading
    private let analytics: any AnalyticsTracking
    private let calendar: Calendar
    private let continueLimit: Int
    private weak var delegate: (any ListemDelegate)?

    /// Devam Et'te "Kaldır" (gizle) — geçmiş verisi silinmez, oturum içinde gizlenir
    /// (`is_hidden`, §4.12); sunucu `is_hidden` alanı F2 kapsamı.
    private var hiddenEpisodeIDs: Set<EpisodeID> = []
    private var loadedSegments: Set<MyListSegment> = []
    private var appeared = false
    private var loadTask: Task<Void, Never>?

    public init(
        favoritesService: FavoritesService,
        continueWatchingService: ContinueWatchingService,
        catalog: any LibraryCatalogReading,
        analytics: any AnalyticsTracking,
        delegate: (any ListemDelegate)?,
        downloadsEnabled: Bool = false,
        continueLimit: Int = 0,
        calendar: Calendar = .current
    ) {
        self.favoritesService = favoritesService
        self.continueWatchingService = continueWatchingService
        self.catalog = catalog
        self.analytics = analytics
        self.delegate = delegate
        visibleSegments = MyListSegment.visible(downloadsEnabled: downloadsEnabled)
        self.continueLimit = continueLimit
        self.calendar = calendar
        segment = visibleSegments.first ?? .favorites
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        trackScreenView()
        guard !appeared else { return }
        appeared = true
        loadTask = Task { await load(segment) }
    }

    /// Testler için: askıdaki yükleme görevini bekler (deterministik).
    func pendingWork() async {
        await loadTask?.value
    }

    /// Segment değişimi (§4.12): analitik + ilk kez görülüyorsa yükle. Düzenleme modundan çıkar.
    public func selectSegment(_ target: MyListSegment) {
        guard visibleSegments.contains(target), target != segment else { return }
        if isEditing {
            endEditing()
        }
        segment = target
        analytics.track("mylist_segment_changed", parameters: ["segment": .string(target.analyticsValue)])
        trackScreenView()
        if !loadedSegments.contains(target) {
            loadTask = Task { await load(target) }
        }
    }

    /// Aktif segmenti yükler (lokal, tek kaynak servislerden + katalog JOIN).
    public func load(_ target: MyListSegment) async {
        switch target {
        case .favorites:
            await loadFavorites()
        case .continueWatching:
            await loadContinue()
        case .downloads:
            loadedSegments.insert(.downloads) // F3 — LibraryKit'te içerik yok
        }
    }

    /// Arka plan senkron + yeniden yükleme (View `.refreshable` / ilk görünüm sonrası, §4.12
    /// "Uzak senkron arka planda"). Senkron hataları yutulur (lokal her zaman gösterilir).
    public func syncAndReload() async {
        async let favoritesSync: Void = trySyncFavorites()
        async let continueSync: Void = trySyncContinue()
        _ = await (favoritesSync, continueSync)
        // Senkron sunucudan yeni ilerleme/favori merge etmiş olabilir; aşağıda YALNIZ aktif
        // segment reload edilir. Aktif OLMAYAN segmentleri bayat bırakmamak için yükleme kaydını
        // sıfırla → sonraki `selectSegment` taze yükler (bulgu #6; Devam Et retention yüzeyi taze
        // olmalı). Aktif segment hemen `load(segment)` ile yeniden kayda girer.
        loadedSegments.removeAll()
        await load(segment)
    }

    private func trySyncFavorites() async {
        try? await favoritesService.synchronize()
    }

    private func trySyncContinue() async {
        try? await continueWatchingService.synchronize()
    }

    // MARK: - Yükleme (segment bazlı)

    private func loadFavorites() async {
        if favorites.isEmpty {
            favoritesState = .loading
        }
        let records = await (try? favoritesService.favorites()) ?? []
        let infos = await catalog.seriesInfo(ids: records.map(\.seriesID))
        favorites = records.map { FavoriteItem.make(record: $0, info: infos[$0.seriesID]) }
        favoritesState = favorites.isEmpty ? .empty : .loaded
        loadedSegments.insert(.favorites)
    }

    private func loadContinue() async {
        if continueItems.isEmpty {
            continueState = .loading
        }
        let records = await ((try? continueWatchingService.continueWatching(limit: continueLimit)) ?? [])
            .filter { !hiddenEpisodeIDs.contains($0.episodeID) }
        async let infosTask = catalog.seriesInfo(ids: records.map(\.seriesID))
        async let numbersTask = catalog.episodeNumbers(ids: records.map(\.episodeID))
        let (infos, numbers) = await (infosTask, numbersTask)
        continueItems = records.map { record in
            ContinueWatchingItem.make(
                record: record,
                info: infos[record.seriesID],
                episodeNumber: numbers[record.episodeID]
            )
        }
        continueState = continueItems.isEmpty ? .empty : .loaded
        loadedSegments.insert(.continueWatching)
    }

    // MARK: - Favoriler: düzenleme modu (çoklu silme, §4.12)

    public func toggleEditing() {
        isEditing.toggle()
        if !isEditing {
            selectedForRemoval.removeAll()
        }
    }

    private func endEditing() {
        isEditing = false
        selectedForRemoval.removeAll()
    }

    public func toggleSelection(_ seriesID: SeriesID) {
        guard isEditing else { return }
        if selectedForRemoval.contains(seriesID) {
            selectedForRemoval.remove(seriesID)
        } else {
            selectedForRemoval.insert(seriesID)
        }
    }

    /// Seçili favorileri kaldırır (çoklu silme). Optimistik (yerel anında); sunucu senkronu
    /// arka planda. Kaldırma sonrası liste yeniden yüklenir ve düzenleme modu kapanır.
    public func removeSelected() async {
        // TODO: (WP-F1-G review, ertelendi) seçilenler tek tek `setFavorite(false)` ile silinir
        // (N ayrı yerel yazma). `FavoritesService`/repository'ye batch kaldırma API'si eklenip
        // tek serileştirilmiş yazmaya indirgenebilir — ayrı iş kalemi.
        let targets = selectedForRemoval
        guard !targets.isEmpty else { return }
        for seriesID in targets {
            await remove(seriesID)
        }
        endEditing()
        await loadFavorites()
        Task { try? await favoritesService.synchronize() }
    }

    /// Tek favori kaldırma (uzun basma context menu → "Favorilerden Kaldır", §4.12).
    public func removeFavorite(_ seriesID: SeriesID) async {
        await remove(seriesID)
        await loadFavorites()
        Task { try? await favoritesService.synchronize() }
    }

    private func remove(_ seriesID: SeriesID) async {
        // Düzenleme modunda context-menu tek kaldırma da seçim setini güncel tutmalı; aksi halde
        // "Kaldır (N)" sayacı, artık var olmayan bir ID'yi sayarak şişer (bulgu #7).
        selectedForRemoval.remove(seriesID)
        do {
            try await favoritesService.setFavorite(false, seriesID: seriesID)
            analytics.track(
                "favorite_remove",
                parameters: ["series_id": .string(seriesID.rawValue), "source": .string("listem")]
            )
        } catch {
            // Yerel yazma başarısız (nadir) — sessizce yut; sonraki yüklemede tutarlı kalır.
        }
    }

    // MARK: - Devam Et: gizle (§4.12 sola kaydır → "Kaldır")

    public func hideContinueItem(_ item: ContinueWatchingItem) {
        hiddenEpisodeIDs.insert(item.episodeID)
        continueItems.removeAll { $0.episodeID == item.episodeID }
        analytics.track(
            "mylist_item_removed",
            parameters: [
                "segment": .string(MyListSegment.continueWatching.analyticsValue),
                "series_id": .string(item.seriesID.rawValue)
            ]
        )
        if continueItems.isEmpty {
            continueState = .empty
        }
    }

    // MARK: - Navigasyon niyetleri (delegate → App)

    /// Favori kartı dokunuş → diziyi kaldığı yerden oynat. Kaldırılmış içerik → detaya (§4.12).
    public func openFavorite(_ item: FavoriteItem) {
        guard item.isAvailable else {
            delegate?.listemOpenDetail(seriesID: item.seriesID)
            return
        }
        analytics.track("favorite_opened", parameters: ["series_id": .string(item.seriesID.rawValue)])
        delegate?.listemPlaySeries(seriesID: item.seriesID)
    }

    /// "Devam Et" kartı → kaldığı konumdan oynat. Kaldırılmış içerik → detaya (§4.12).
    public func openContinue(_ item: ContinueWatchingItem) {
        guard item.isAvailable else {
            delegate?.listemOpenDetail(seriesID: item.seriesID)
            return
        }
        var parameters: [String: AnalyticsValue] = [
            "series_id": .string(item.seriesID.rawValue),
            "progress_pct": .int(item.progressPercent)
        ]
        // Bölüm numarası bilinmiyorsa (katalog JOIN vermedi) parametreyi ATLA: 0 geçersiz
        // 1-tabanlı numaradır ve huniyi kirletir (bulgu #8).
        if let episodeNumber = item.episodeNumber {
            parameters["episode_number"] = .int(episodeNumber)
        }
        analytics.track("continue_watching_tapped", parameters: parameters)
        delegate?.listemResumeEpisode(
            seriesID: item.seriesID,
            episodeID: item.episodeID,
            startPositionSec: item.positionSec
        )
    }

    public func openDetail(_ seriesID: SeriesID) {
        delegate?.listemOpenDetail(seriesID: seriesID)
    }

    public func shareFavorite(_ seriesID: SeriesID) {
        delegate?.listemShare(seriesID: seriesID)
    }

    /// Boş durum CTA'ları (02 §3: CTA kullanıcıyı içeriğe geri götürür).
    public func openDiscover() {
        delegate?.listemRequestsDiscover()
    }

    public func openHome() {
        delegate?.listemRequestsHome()
    }

    /// "Devam Et" kartının son izleme zamanı kategorisi (View lokalize eder).
    public func relativeDay(for item: ContinueWatchingItem, now: Date = Date()) -> RelativeDay {
        RelativeDay.between(item.watchedAt, and: now, calendar: calendar)
    }

    // MARK: - İç

    private func trackScreenView() {
        analytics.track(
            "screen_view",
            parameters: ["screen_name": .string("listem"), "segment": .string(segment.analyticsValue)]
        )
    }
}
