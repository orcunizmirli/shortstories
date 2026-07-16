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

    /// Bekleyen bağlamsal oynatma isteği: RootTabView (Ana Sayfa görünür olunca / yeni intent gelince)
    /// `seedFeedWithPendingPlaybackIfNeeded()` ile TÜKETİR → `PlaybackFeedResolver` bunu feed-entry
    /// seed'ine çevirir. `@ObservationTracked` olduğundan `.onChange` sıcak sekmede yeni intent'i yakalar.
    private(set) var pendingPlayback: PlaybackIntent?

    /// Mount edilen `PlayerFeedView`'ı süren feed-entry (nil → For You baştan). Seed çözülünce set edilir.
    private(set) var feedEntry: FeedEntry?
    /// Feed remount jetonu (SwiftUI `.id`): seed çözülünce artırılır → `PlayerFeedView` yeni `entry` ile
    /// yeniden kurulur (PlayerKit seed'i yalnız init'te/ilk aktivasyonda tüketir; canlı VC'ye enjekte
    /// edilemez). Havuz kompozisyon kökünde (koordinatörde) yaşadığından remount player'ları KORUR
    /// (VC.deinit → director.teardown(keepPlayers:true)).
    private(set) var feedMountToken = 0
    /// Sıra-dışı biten katalog fetch'i güncel seed'i ezmesin diye üretim sayacı (last-intent-wins).
    private var seedGeneration = 0
    /// SS-061: Ana Sayfa sekmesi aktif mi (pause/resume sinyali). `TabCoordinator` sekme değişiminde yazar.
    private(set) var isHomeActive = true

    /// Cross-feature "bu diziyi oynat" niyeti (deep-link/DiziDetay/Listem/Ana Sayfa → PlayerFeed).
    /// `episodeID` önceden çözülmüş hedeftir (Ana Sayfa/Listem "devam et" kayıtları taşır) ve
    /// `episodeNumber`'a göre önceliklidir; `episodeNumber` deep-link/DiziDetay'ın taşıdığı 1-tabanlı
    /// numaradır (App katalogdan bölüm-ID'ye çözer). İkisi de nil → dizinin ilk oynatılabilir bölümü.
    struct PlaybackIntent: Equatable, Sendable {
        let seriesID: SeriesID
        let episodeNumber: Int?
        let episodeID: EpisodeID?
        let startPositionSec: Double

        init(
            seriesID: SeriesID,
            episodeNumber: Int? = nil,
            episodeID: EpisodeID? = nil,
            startPositionSec: Double = 0
        ) {
            self.seriesID = seriesID
            self.episodeNumber = episodeNumber
            self.episodeID = episodeID
            self.startPositionSec = startPositionSec
        }
    }

    /// SS-062 intent→feed-entry çözümleyicisi (katalog fetch; SAF eşleme `PlaybackIntentMapper`'da).
    private let feedResolver: PlaybackFeedResolver

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
        feedViewModel = composition.makePlayerFeedViewModel()
        feedResolver = PlaybackFeedResolver(catalog: composition.catalog)
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

    /// SwiftUI köprüsü — Ana Sayfa tab view'ı bunu gömer (delegate = self). `entry`: çözülmüş
    /// bağlamsal seed (nil → For You baştan). RootTabView `.id(feedMountToken)` ile yeni seed'de
    /// remount eder ki PlayerKit init-time seed'i taze `entry`'yi görsün.
    func makePlayerFeedView() -> PlayerFeedView {
        PlayerFeedView(
            viewModel: feedViewModel,
            playerPool: playerPool,
            prefetch: prefetch,
            analytics: composition.dependencies.analytics,
            delegate: self,
            entry: feedEntry
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

    /// TabCoordinator sekme değişiminde çağırır (SS-061 pause/resume sinyali). Pause,
    /// `PlayerFeedViewController.viewWillDisappear` tarafından otomatik yapılır (SwiftUI sekme
    /// değişiminde view hiyerarşiden çıkar → §10.4/11) ve KAREYİ korur.
    func setActive(_ isActive: Bool) {
        isHomeActive = isActive
        // Pause SİMETRİK ve kayıpsızdır: ayrılışta `viewWillDisappear` pause + kareyi korur; dönüşte
        // kullanıcı tek tap ile tam kaldığı kareden devam eder.
        //
        // Otomatik resume (dönüşte kendiliğinden oynatma) App-only KAPSAM DIŞIDIR: PlayerKit'in kapalı
        // public yüzeyi bir resume kontrolü (aktif `handle.play()`) sunmaz; yeni feed-entry API'si yalnız
        // SEED sağlar (belirli içerik/konumdan İLK aktivasyon). Feed-entry ile re-seed teknik olarak
        // mümkün ama korunan kareyi kaybedip sıfırdan (yinelenen `video_start` + yeniden buffer) başlatır
        // → kare-koruyan pause'a göre NET REGRESYON. Bu yüzden App yalnız aktif/pasif sinyalini üretir;
        // kare-doğru auto-resume, feature resume kontrolü eklenince bu sinyale bağlanır (SS-061 sonraki dilim).
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

    /// PlayerFeed göründüğünde / yeni intent geldiğinde çağrılır (RootTabView `.task`/`.onChange`).
    /// Bekleyen bağlamsal oynatma isteğini TÜKETİR (deep-link `.play`/`.episode`, DiziDetay/Listem
    /// "oynat", Ana Sayfa "devam et") ve `PlaybackFeedResolver` ile feed-entry seed'ine çevirir:
    /// katalogdan hedef bölüm çözülür, dizinin bölümleri `feedState`e akar ve `feedEntry` + remount
    /// jetonu set edilir → `PlayerFeedView(entry:)` doğru içerik/konumdan başlar. Pending yoksa no-op.
    func seedFeedWithPendingPlaybackIfNeeded() {
        guard let intent = consumePendingPlayback() else { return }
        seedGeneration &+= 1
        let generation = seedGeneration
        let resolver = feedResolver
        Task { [weak self] in
            let seed = await resolver.resolve(intent)
            // Sıra-dışı biten fetch güncel seed'i ezmesin (last-intent-wins); çözülemezse feed'e
            // dokunma (For You/mevcut içerik korunur — sessiz düşüş, ağ hatası feed'in kendi durumunda).
            guard let self, let seed, seedGeneration == generation else { return }
            applySeed(seed)
        }
    }

    /// Çözülmüş seed'i uygular: feed öğeleri + entry set edilir, remount jetonu artırılır
    /// (RootTabView `.id` → `PlayerFeedView` yeni `entry` ile yeniden kurulur, seed ilk aktivasyonda tüketilir).
    private func applySeed(_ seed: PlaybackFeedSeed) {
        feedViewModel.feedState = FeedState(items: seed.items)
        feedEntry = seed.entry
        feedMountToken &+= 1
    }

    /// SS-065: Ana Sayfa "devam et" yüzeyinden oynatma — kaldığı BÖLÜM ve pozisyondan. Kayıt bölüm
    /// ID'sini doğrudan taşır (numara lookup'ı yok) → seed tam bölüme çözülür.
    func resumeContinue(_ entry: ContinueWatchingEntryModel.Entry) {
        requestPlayback(PlaybackIntentMapper.continueIntent(
            seriesID: entry.seriesID,
            episodeID: entry.episodeID,
            positionSec: entry.positionSec
        ))
    }

    /// SS-050/062: bölüm kilidi açıldı (coin/reklam/VIP) → feed'de o bölümü oynatılabilir işaretle.
    /// Yeni `feedState` `PlayerFeedView.updateUIViewController` üzerinden PlayerKit'e diff'li akar
    /// ve `PlayerFeedViewController.apply(state:)` kilitli kartı YERİNDE reactivate eder (04 §9.2).
    /// `feedMountToken` BİLİNÇLİ artırılmaz: reactivation korunan kareyi kaybetmemek için remount
    /// DEĞİL diff'li apply olmalıdır (remount seed'i yeniden tüketip sıfırdan başlatır — regresyon).
    /// Karar SAF (`FeedUnlockReducer`): bölüm feed'de yoksa / zaten oynatılabilirse feed'e dokunulmaz.
    private func applyUnlock(_ episodeID: EpisodeID) {
        guard let updatedItems = FeedUnlockReducer.applyingUnlock(
            of: episodeID,
            to: feedViewModel.feedState.items
        ) else { return }
        feedViewModel.feedState = FeedState(items: updatedItems)
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
