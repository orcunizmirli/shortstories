import AppFoundation
import ContentKit
import Foundation
import Observation

/// Kesfet yükleme/durum makinesi (SS-070/071/074). @Observable/@MainActor; SwiftUI View ince
/// kalır, tüm türetim `KesfetComposition` (saf) + bu modeldedir. Stale-while-revalidate cache
/// (bayat-önce-göster), tür chip filtresi (raf-içi kombinasyon), oturum-içi filtre kalıcılığı ve
/// pull-to-refresh burada yönetilir.
@MainActor
@Observable
public final class KesfetModel {
    /// Ana yükleme durumu (02 §3 sözleşmesi). Cache gösterilirken revalidasyon başarısız olursa
    /// durum `.loaded` kalır (bayat içerik korunur), offline'da banner yükselir.
    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case error
        case offline
    }

    // MARK: - Durum (Observable)

    public private(set) var loadState: LoadState = .idle
    /// Son iyi içerik (cache veya ağ). `composition` bundan türetilir.
    public private(set) var content: DiscoverContent?
    public private(set) var showsOfflineBanner = false
    /// Seçili tür filtresi — UI'ı süren state @Observable grafiğinde YAŞAR (SS-071/074). Çip
    /// seçimi bunu değiştirir → Observation bildirimi → View filtreye canlı tepki verir. Session
    /// store yalnız oturum-içi KALICILIK içindir (kaynak-of-truth değil).
    public private(set) var selectedGenreID: String?

    // MARK: - Bağımlılıklar

    private let catalog: any CatalogServicing
    private let session: DiscoverSessionStore
    private let analytics: any AnalyticsTracking
    private let now: @Sendable () -> Date
    private let ttl: Duration
    private weak var delegate: (any KesfetDelegate)?

    private var trackedScreenView = false
    /// revalidate kuşak jetonu — eşzamanlı discover() sıra-dışı tamamlanınca geç dönen bayat
    /// yanıt taze yanıtı EZMESİN ve TTL'i bayatla sıfırlamasın (en son BAŞLAYAN istek kazanır).
    private var revalidateGeneration = 0

    public init(
        catalog: any CatalogServicing,
        session: DiscoverSessionStore,
        analytics: any AnalyticsTracking,
        delegate: (any KesfetDelegate)?,
        ttl: Duration = CacheFreshness.discoverTTL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.catalog = catalog
        self.session = session
        self.analytics = analytics
        self.delegate = delegate
        self.ttl = ttl
        self.now = now
        // Oturum kalıcılığından başlangıç filtresini al (kaynak-of-truth model'de yaşar).
        selectedGenreID = session.selectedGenreID
    }

    /// Saf türetilmiş kompozisyon — View doğrudan çizer.
    public var composition: KesfetComposition {
        guard let content else { return .empty(selectedGenreID: selectedGenreID) }
        return KesfetComposition.compose(content: content, selectedGenreID: selectedGenreID, now: now())
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        Task { await load() }
    }

    /// İlk yükleme (SWR): cache varsa anında göster; taze ise ağ turu atlanır, bayatsa arkada
    /// revalidasyon. Cache yoksa skeleton + ağ. Testler doğrudan `await` eder.
    public func load() async {
        trackScreenViewIfNeeded()
        if let cached = session.cached {
            content = cached.content
            loadState = .loaded
            showsOfflineBanner = false
            if CacheFreshness.isFresh(storedAt: cached.storedAt, ttl: ttl, now: now()) {
                return
            }
            await revalidate()
        } else {
            loadState = .loading
            await revalidate()
        }
    }

    /// Pull-to-refresh (02 §4.10): tazeliği yok say, her zaman revalidate.
    public func refresh() async {
        analytics.track("discover_refreshed", parameters: [:])
        await revalidate()
    }

    private func revalidate() async {
        revalidateGeneration += 1
        let token = revalidateGeneration
        do {
            let fresh = try await catalog.discover()
            guard token == revalidateGeneration else { return } // üstü örtüldü: bayat yazma yok
            content = fresh
            session.save(fresh, at: now())
            loadState = .loaded
            showsOfflineBanner = false
        } catch let error as AppError {
            guard token == revalidateGeneration else { return }
            handle(error)
        } catch {
            guard token == revalidateGeneration else { return }
            handle(.unexpected(underlying: String(describing: error)))
        }
    }

    /// Hata politikası (02 §4.10 durum tablosu): cache varsa cache korunur; offline'da banner,
    /// diğer hatada sessiz bayat-gösterim. Cache yoksa tam ekran offline/error.
    private func handle(_ error: AppError) {
        let isOffline = error == .network(.offline)
        if content != nil {
            loadState = .loaded
            showsOfflineBanner = isOffline
        } else {
            loadState = isOffline ? .offline : .error
        }
    }

    // MARK: - Tür filtresi (SS-071/074)

    /// Çip seçimi: raf yapısı korunur, içerik filtrelenir (02 §4.10). Yeni ağ turu YOK
    /// (istemci-içi filtre); seçim oturum store'una yazılır (kalıcılık).
    public func selectGenre(_ genreID: String?) {
        guard genreID != selectedGenreID else { return }
        selectedGenreID = genreID // @Observable state → View güncellenir
        session.selectedGenreID = genreID // oturum kalıcılığı
        analytics.track("genre_filter_selected", parameters: ["genre_id": .string(genreID ?? "all")])
    }

    /// Filtre boş sonuç CTA'sı: filtreyi temizle (02 §4.10 boş durum).
    public func clearFilter() {
        selectGenre(nil)
    }

    // MARK: - Etkileşim aksiyonları

    /// Raf/ızgara kartı → `DiziDetay` (§4.10). `series_detail_view` DiziDetay tarafından atılır.
    public func selectSeries(_ series: Series, shelfID: String, position: Int) {
        analytics.track(
            "discover_card_tapped",
            parameters: [
                "series_id": .string(series.id.rawValue),
                "shelf_id": .string(shelfID),
                "position": .int(position)
            ]
        )
        delegate?.kesfetDidSelectSeries(series.id, shelfID: shelfID)
    }

    /// Banner dokunuşu → deep link çözümü (§4.10: banner action'ları Route enum'undan geçer).
    /// Çözülemeyen banner deep link'i `deeplink_fallback` ile `home`'a düşer (§8.4 kural 3).
    public func selectBanner(_ banner: Banner, position: Int) {
        analytics.track(
            "discover_banner_tapped",
            parameters: ["banner_id": .string(banner.id), "position": .int(position)]
        )
        if let route = DeepLinkResolver.route(from: banner.deeplink) {
            delegate?.kesfetDidOpenRoute(route)
        } else {
            analytics.track("deeplink_fallback", parameters: ["reason": .string("unknown_path")])
            delegate?.kesfetDidOpenRoute(.home)
        }
    }

    /// Raf "Tümü" → dikey ızgara sayfası (§4.10).
    public func selectSeeAll(shelf: KesfetComposition.Shelf) {
        analytics.track("discover_shelf_see_all", parameters: ["shelf_id": .string(shelf.id)])
        delegate?.kesfetDidSelectSeeAll(collectionID: shelf.id, title: shelf.title)
    }

    /// Üst arama çubuğu butonu → `Arama` (§4.10).
    public func openSearch() {
        delegate?.kesfetRequestsSearch()
    }

    private func trackScreenViewIfNeeded() {
        guard !trackedScreenView else { return }
        trackedScreenView = true
        analytics.track("screen_view", parameters: ["screen_name": .string("kesfet")])
    }
}
