import AppFoundation
import ContentKit
import Foundation
import Observation

/// Player feed sağ-ray "Bölümler" → hızlı bölüm-değiştirici sheet modeli (04 §8.5 / SS-033).
/// DiziDetay'ın TAM detay sayfasından farkı: feed içinde kalıp bir bölüme atlamak için ince liste.
/// Bölüm listesi + kilit durumu `CatalogServicing`/`EntitlementChecking` portlarından türer (DiziDetay
/// ile AYNI kaynaklar). Bir satıra dokununca `delegate` App'e iletir (App feed'i o bölüme geçirir +
/// sheet'i kapatır). WalletKit/PlayerKit import EDİLMEZ — kilit çözümü porttan (R2).
@MainActor
@Observable
public final class BolumListesiModel {
    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        case error
    }

    /// Bir bölüm satırı (ızgara/liste öğesi). `isPlayable`: kullanıcı hemen oynatabilir (free/unlocked/
    /// entitled). `isCurrent`: şu an feed'de aktif olan bölüm (vurgulama). Kilitli satır da dokunulabilir —
    /// dokununca oynatma denenir, kilitliyse mevcut UnlockSheet akışı devreye girer (App).
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: EpisodeID
        public let number: Int
        public let title: String?
        public let isPlayable: Bool
        public let isCurrent: Bool
        /// Henüz yayınlanmadı (publishedAt gelecekte/nil) → takvim hücresi; oynatılamaz, seçim no-op.
        public let isScheduled: Bool

        public init(id: EpisodeID, number: Int, title: String?, isPlayable: Bool, isCurrent: Bool, isScheduled: Bool) {
            self.id = id
            self.number = number
            self.title = title
            self.isPlayable = isPlayable
            self.isCurrent = isCurrent
            self.isScheduled = isScheduled
        }
    }

    public private(set) var loadState: LoadState = .loading
    public private(set) var rows: [Row] = []
    public let seriesTitle: String

    private let seriesID: SeriesID
    private let currentEpisodeID: EpisodeID?
    private let catalog: any CatalogServicing
    private let entitlement: any EntitlementChecking
    private let now: @Sendable () -> Date
    private weak var delegate: (any BolumListesiDelegate)?

    public init(
        series: Series,
        currentEpisodeID: EpisodeID?,
        catalog: any CatalogServicing,
        entitlement: any EntitlementChecking,
        delegate: (any BolumListesiDelegate)?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        seriesTitle = series.title
        seriesID = series.id
        self.currentEpisodeID = currentEpisodeID
        self.catalog = catalog
        self.entitlement = entitlement
        self.now = now
        self.delegate = delegate
    }

    /// Bölümleri (ilk sayfa) çekip satırlara türetir. Kilit: `free`/`unlocked` erişim VEYA entitlement
    /// (VIP/daha önce açılmış) → oynatılabilir. Hata → `.error` (View "Tekrar Dene" gösterir).
    public func load() async {
        loadState = .loading
        do {
            let page = try await catalog.episodes(seriesId: seriesID, cursor: nil)
            let clock = now()
            var derived: [Row] = []
            for episode in page.items {
                // `||` sağ-tarafı autoclosure'dır (async çağrı barındıramaz) → entitlement kontrolü
                // ayrı if-expression'da: erişim free/unlocked değilse porta (VIP/açılmış) sorulur.
                let entitled = if episode.access.kind == .free || episode.access.kind == .unlocked {
                    true
                } else {
                    await entitlement.hasAccess(to: episode.id)
                }
                // Yayın durumu (DiziDetay ile simetrik, 05 §2.2): yayınlanmamış (scheduled) bölüm entitled
                // olsa bile OYNATILAMAZ — akışı yok, feed'e geçirilse kırık oynatma; scheduled göstergesi çizilir.
                let isPublished = episode.isPublished(at: clock)
                derived.append(Row(
                    id: episode.id,
                    number: episode.index,
                    title: episode.title,
                    isPlayable: isPublished && entitled,
                    isCurrent: episode.id == currentEpisodeID,
                    isScheduled: !isPublished
                ))
            }
            rows = derived
            loadState = .loaded
        } catch {
            loadState = .error
        }
    }

    /// Bir bölüme dokunuldu → App'e ilet (feed o bölüme geçer; kilitliyse orada UnlockSheet açılır).
    /// Yayınlanmamış (scheduled) bölüm no-op (DiziDetay.selectEpisode ile simetrik): akışı yok.
    public func selectEpisode(_ row: Row) {
        guard !row.isScheduled else { return }
        delegate?.bolumListesiDidSelectEpisode(number: row.number, in: seriesID)
    }

    /// Kullanıcı listeyi kapattı.
    public func dismiss() {
        delegate?.bolumListesiRequestsDismiss()
    }
}

/// BolumListesi navigasyon niyetleri → App koordinatörü bağlar (04 §2.4). PlayerKit/WalletKit
/// import EDİLMEZ; bağlam koordinatördedir (R2). @MainActor, zayıf referans.
@MainActor
public protocol BolumListesiDelegate: AnyObject {
    /// Bölüme dokunuldu → feed'i bu bölüme geçir (App `requestPlayback` + sheet'i kapat).
    func bolumListesiDidSelectEpisode(number: Int, in seriesID: SeriesID)
    /// Kullanıcı listeyi kapattı.
    func bolumListesiRequestsDismiss()
}
