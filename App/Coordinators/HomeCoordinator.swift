import AppFoundation
import ContentKit
import DiscoverKit
import Foundation
import Observation
import PlayerKit
import SwiftUI

/// Ana Sayfa koordinatörü (03 §3.1): `PlayerFeed` + üstündeki sheet/push yüzeyleri. PlayerFeed'in
/// oynatma grafiği (havuz/prefetch/viewModel) BURADA yaşar — sekme değişimlerinde korunur (havuz
/// boşaltılmaz, 02 §2.2). `PlayerFeedDelegate` niyetleri (favori/paylaş/DiziDetay/UnlockSheet)
/// burada karşılanır (04 §2.2/§2.4): VC hiçbir ekran açmaz, yalnız niyet üretir.
@Observable
@MainActor
final class HomeCoordinator {
    private let composition: AppComposition
    private let walletFlow: WalletFlowCoordinator
    /// Sekmeler arası geçiş + bağlamsal oynatma için üst koordinatör (zayıf — döngü yok).
    weak var tabCoordinator: TabCoordinator?

    // MARK: - Oynatma grafiği (kompozisyon kökünden, sekme ömrünce tek instance)

    let feedViewModel: PlayerFeedViewModel
    let playerPool: PlayerPool
    let prefetch: PrefetchController

    // MARK: - Navigasyon durumu

    /// Ana Sayfa stack'i — dizi adına dokununca `DiziDetay` push edilir (02 §4.3.2 katman 2).
    var path = NavigationPath()
    /// SS-065 "kaldığın yerden devam et" giriş yüzeyi durumu.
    let continueEntry: ContinueWatchingEntryModel

    /// SS-062 (App feed yükleme) bağlanana kadar bağlamsal oynatma isteğini tutar; feed sayfalama
    /// dilimi bu intent'i tüketip doğru bölümü aktive edecektir.
    private(set) var pendingPlayback: PlaybackIntent?

    /// Cross-feature "bu diziyi oynat" niyeti (Listem/DiziDetay/Profil → PlayerFeed).
    struct PlaybackIntent: Equatable {
        let seriesID: SeriesID
        let episodeNumber: Int?
        let startPositionSec: Double
    }

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
        feedViewModel = composition.makePlayerFeedViewModel()
        let pool = composition.makePlayerPool(size: 3)
        playerPool = pool
        prefetch = composition.makePrefetchController(pool: pool)
        continueEntry = ContinueWatchingEntryModel(
            service: composition.continueWatchingService,
            catalog: composition.libraryCatalogReading
        )
        // Kilit açıldığında feed'e haber ver (04 §9.2): kilitli kart yerinde yeniden oynar.
        walletFlow.onEpisodeUnlocked = { [weak self] episodeID in
            self?.applyUnlock(episodeID)
        }
    }

    /// SwiftUI köprüsü — Ana Sayfa tab view'ı bunu gömer (delegate = self).
    func makePlayerFeedView() -> PlayerFeedView {
        PlayerFeedView(
            viewModel: feedViewModel,
            playerPool: playerPool,
            prefetch: prefetch,
            analytics: composition.dependencies.analytics,
            delegate: self
        )
    }

    /// Ana Sayfa stack push hedefi (DiziDetay). Delegate = TabCoordinator (stack-bağımsız DiziDetay
    /// niyetleri: oynat/unlock/paylaş/Keşfet — hiçbiri Home stack'ine push etmez).
    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case let .diziDetay(seriesID, source):
            DiziDetayView(model: composition.makeDiziDetayModel(seriesID: seriesID, source: source, delegate: tabCoordinator))
        case .arama, .ayarlar:
            EmptyView() // Ana Sayfa stack'inde bu hedefler push edilmez.
        }
    }

    // MARK: - Sekme etkinliği (SS-061 pause/resume sinyali)

    /// TabCoordinator sekme değişiminde çağırır. Pause, `PlayerFeedViewController.viewWillDisappear`
    /// tarafından otomatik yapılır (SwiftUI sekme değişiminde view hiyerarşiden çıkar → §10.4/11).
    /// Ana Sayfa'ya DÖNÜŞTE resume için PlayerKit'te public bir kontrol girişi gerekir (feature
    /// sealed public yüzey: init + apply(state:) + delegate); bu köprü hazır, resume feature'ın
    /// sonraki diliminde (viewWillAppear) bağlanacak — App yalnız sinyali üretir (02 §2.3).
    func setActive(_ isActive: Bool) {
        // Ana Sayfa'ya DÖNÜŞTE resume: PlayerKit `viewWillDisappear` pause eder ama simetrik resume
        // için VC'de `viewWillAppear` → director.resume kancası gerekir; bu public kontrol girişi
        // PlayerKit'te (feature) henüz yok → App yalnız sinyali üretir.
        // TODO(SS-061/PlayerKit): feature public resume girişi eklenince `isActive` bu kancaya bağlanır.
        _ = isActive
    }

    // MARK: - Bağlamsal oynatma (SS-062 App feed dilimi tüketir)

    func requestPlayback(_ intent: PlaybackIntent) {
        // PlayerFeed'i öne getir: DiziDetay/başka bir push altında GİZLİ kalmasın (02 §4.3.2). Ana
        // Sayfa stack'i köke sıfırlanır ki bağlamsal oynatma doğrudan feed'de görünsün.
        if !path.isEmpty {
            path = NavigationPath()
        }
        pendingPlayback = intent
        // Feed hazır olunca `seedFeedWithPendingPlaybackIfNeeded()` bu intent'i tüketir (RootTabView
        // PlayerFeed .task/.onChange ile çağırır).
    }

    func consumePendingPlayback() -> PlaybackIntent? {
        defer { pendingPlayback = nil }
        return pendingPlayback
    }

    /// PlayerFeed göründüğünde / yeni intent geldiğinde çağrılır (RootTabView). Bekleyen bağlamsal
    /// oynatma isteğini TÜKETİR — deep-link `.play`/`.episode`, "Devam Et" banner'ı ve Listem "oynat"
    /// hep buradan feed'e akar. Böylece `consumePendingPlayback()` ölü kod değildir (intent saklanıp
    /// hiç okunmadan kalmaz).
    func seedFeedWithPendingPlaybackIfNeeded() {
        guard let intent = consumePendingPlayback() else { return }
        // TODO(SS-062): intent → FeedItem(ler) kur (katalog/episode fetch) + `feedViewModel.feedState`e
        // seed et; `PlayerFeedView.updateUIViewController` diff'li `apply(state:)` ile doğru bölümü/
        // pozisyonu aktive eder. Feed yükleme dilimi (SS-062) bağlanınca tamamlanır.
        _ = intent
    }

    /// SS-065: "devam et" yüzeyinden oynatma — kaldığı bölüm/pozisyondan.
    func resumeContinue(_ entry: ContinueWatchingEntryModel.Entry) {
        requestPlayback(PlaybackIntent(
            seriesID: entry.seriesID,
            episodeNumber: nil,
            startPositionSec: entry.positionSec
        ))
    }

    private func applyUnlock(_ episodeID: EpisodeID) {
        // TODO(SS-062): feedState'i güncelle → apply(state:) kilitli kartı yerinde reactivate eder
        // (PlayerFeedViewController.reactivatableUnlockIndex). Feed yüklemesi bağlanınca aktifleşir.
        _ = episodeID
    }
}

// MARK: - PlayerFeedDelegate (04 §2.4) — VC niyetleri App'te birleşir

extension HomeCoordinator: PlayerFeedDelegate {
    func playerFeed(
        _: PlayerFeedViewController,
        didReachLockedEpisode episode: Episode,
        in series: Series
    ) {
        // Kilitli bölüm (04 §9.1 adım 3): UnlockSheet player üzerine sunulur, video kilit karesinde.
        walletFlow.presentUnlock(for: episode, in: series, source: .autoAdvance)
    }

    func playerFeed(_: PlayerFeedViewController, didChangeActiveIndex _: Int, episode _: Episode?) {
        // F1: aktif kart değişimi — SS-062 feed sayfalama + izleme-ilerleme heartbeat'i Faz 2'de.
    }

    func playerFeedDidRequestMoreItems(_: PlayerFeedViewController) {
        // TODO(SS-062): sonraki feed sayfası / yeni dizi önerisi yüklenip feedState'e eklenir.
    }

    func playerFeed(_: PlayerFeedViewController, didRequestSeriesDetail series: Series) {
        path.append(AppRoute.diziDetay(seriesID: series.id, source: .playerFeed))
    }

    func playerFeed(
        _: PlayerFeedViewController,
        didRequestFavoriteToggle series: Series,
        episode _: Episode?
    ) {
        // Favori YALNIZ ray butonundan (02 §4.3.2). Tek kaynak: FavoritesService (SS-121).
        let favorites = composition.favoritesService
        let seriesID = series.id
        Task { try? await favorites.toggleFavorite(seriesID) }
    }

    func playerFeed(
        _: PlayerFeedViewController,
        didRequestShare series: Series,
        episode: Episode?
    ) {
        // Deep link üretimi App katmanında (SS-142): bölüm bağlamı varsa bölüm linki, yoksa dizi.
        let url = episode.map { DeepLinkFactory.episodeURL(series.id, episodeNumber: $0.index) }
            ?? DeepLinkFactory.seriesURL(series.id)
        tabCoordinator?.sharePresenter.share(url)
    }

    func playerFeed(_: PlayerFeedViewController, didRequestEpisodeList _: Series) {
        // TODO(04 §8.5): BolumListesi sheet'i — PlayerKit'te public bir liste view'ı yok (F1 iskelet).
    }

    func playerFeed(_: PlayerFeedViewController, didRequestPlaybackSpeedMenu _: Double) {
        // TODO(04 §8.2): hız menüsü UI'ı — F1 iskelet (PlayerFeedDelegate sözleşmesi).
    }

    func playerFeed(_: PlayerFeedViewController, didRequestSubtitleMenu _: Episode) {
        // TODO(04 §8.3 / SS-046): altyazı seçim sheet'i — F1 iskelet.
    }
}
