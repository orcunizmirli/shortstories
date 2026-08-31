import AppFoundation
import ContentKit
import DiscoverKit
import Foundation
import Observation
import PlayerKit
import ProfileKit
import SwiftUI

/// Ana Sayfa koordinatörü (03 §3.1): `PlayerFeed` + üstündeki sheet/push yüzeyleri. PlayerFeed'in
/// oynatma grafiği (havuz/prefetch/viewModel) BURADA yaşar — sekme değişimlerinde korunur (havuz
/// boşaltılmaz, 02 §2.2). `PlayerFeedDelegate` niyetleri (favori/paylaş/DiziDetay/UnlockSheet)
/// burada karşılanır (04 §2.2/§2.4): VC hiçbir ekran açmaz, yalnız niyet üretir.
@Observable
@MainActor
final class HomeCoordinator {
    let composition: AppComposition // internal: HomeCoordinator+FeedUnlock uzantısı entitlement portu için okur
    private let walletFlow: WalletFlowCoordinator
    /// Sekmeler arası geçiş + bağlamsal oynatma için üst koordinatör (zayıf — döngü yok).
    weak var tabCoordinator: TabCoordinator?

    // MARK: - Oynatma grafiği (kompozisyon kökünden, sekme ömrünce tek instance)

    let feedViewModel: PlayerFeedViewModel
    let playerPool: PlayerPool
    let prefetch: PrefetchController

    // MARK: - Navigasyon durumu

    /// Ana Sayfa stack'i — dizi adına dokununca `DiziDetay` push edilir (02 §4.3.2 katman 2).
    var path: [AppRoute] = []
    /// SS-065 "kaldığın yerden devam et" giriş yüzeyi durumu.
    let continueEntry: ContinueWatchingEntryModel
    /// BolumListesi sheet'i (04 §8.5) — non-nil olunca RootTabView sunar; seçim/kapamada temizlenir.
    private(set) var bolumListesiModel: BolumListesiModel?
    /// Feed'de şu an aktif olan bölüm (BolumListesi vurgusu). `didChangeActiveIndex` günceller.
    private(set) var activeEpisodeID: EpisodeID?
    /// Hız menüsü (04 §8.2) açık mı + hangi hız işaretli — non-nil olunca RootTabView action-sheet sunar.
    private(set) var speedMenuCurrentRate: Double?
    /// Altyazı menüsü (04 §8.3 / SS-046) seçenekleri — non-nil olunca RootTabView action-sheet sunar
    /// (güncel seçim canlı `composition.languagePreferences`'tan okunur). Aktif dizinin sunduğu diller.
    private(set) var subtitleChoices: [SubtitleLanguage]?

    /// Bekleyen bağlamsal oynatma isteği; RootTabView tüketir → `PlaybackFeedResolver` feed-entry seed'ine çevirir.
    private(set) var pendingPlayback: PlaybackIntent?

    /// Mount edilen `PlayerFeedView`'ı süren feed-entry (nil → For You baştan). Seed çözülünce set edilir.
    private(set) var feedEntry: FeedEntry?
    /// Feed remount jetonu (SwiftUI `.id`): seed çözülünce artırılır → `PlayerFeedView` yeni `entry` ile kurulur
    /// (havuz koordinatörde yaşadığından remount player'ları KORUR: VC.deinit → teardown(keepPlayers:true)).
    private(set) var feedMountToken = 0
    /// Sıra-dışı biten katalog fetch'i güncel seed'i ezmesin diye üretim sayacı (last-intent-wins).
    private var seedGeneration = 0
    /// SS-061: Ana Sayfa sekmesi aktif mi (pause/resume sinyali). `TabCoordinator` sekme değişiminde yazar.
    private(set) var isHomeActive = true

    /// Cross-feature "bu diziyi oynat" niyeti. `episodeID` önceden çözülmüş hedef (Ana Sayfa/Listem "devam et")
    /// ve `episodeNumber`'a önceliklidir; ikisi de nil → dizinin ilk oynatılabilir bölümü (App katalogdan çözer).
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
    /// Hesap-değişimi gözlemcisi — app ömrü boyunca canlı (RewardsCoordinator deseni).
    @ObservationIgnored private var accountObserver: Task<Void, Never>?
    /// VIP-grant (applyVIPUnlock) ile işaretli VIP-REVOCABLE bölümler (#4); bireysel coin/reklam unlock KALICI, girmez.
    @ObservationIgnored var vipGrantedEpisodes: Set<EpisodeID> = []
    /// Entitlement-düşüşü gözlemcisi — app ömrü boyunca canlı ([weak self], `accountObserver` deseni).
    @ObservationIgnored var entitlementObserver: Task<Void, Never>?

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
        // VIP aktifleşti → feed'deki TÜM kilitli bölümleri reaktive et (standalone VIP, audit LOW).
        walletFlow.onVIPActivated = { [weak self] in
            self?.applyVIPUnlock()
        }
        startObservingAccountSwitch()
        startObservingEntitlementRevocation()
    }

    /// Hesap DEĞİŞİMİNDE (userID farklı bir hesaba geçince) feed durumunu sıfırlar — feedViewModel/pool
    /// TabCoordinator ömrü boyunca yaşar, switch'te yeniden yaratılmaz → önceki hesabın feedState'i (özellikle
    /// applyUnlock ile `.unlocked` işaretlenmiş bölümler) yeni hesaba SIZAR: PlayerPool.isPlayable `.unlocked`'a
    /// entitlement sormadan güvendiğinden B, A'nın açtığı bölümü paywall'suz oynatır (05 §3.3, SS-132). link
    /// (guest→aynı userID) / session-death / re-auth reset TETİKLEMEZ; yalnız gerçek switch. RewardsCoordinator
    /// deseniyle simetrik.
    private func startObservingAccountSwitch() {
        let session = composition.dependencies.session
        accountObserver = Task { [weak self] in
            var lastUserID: String?
            for await state in session.stateUpdates {
                // lastUserID YALNIZ non-nil'de güncellenir → nil-ara-durumdan (loggedOut) geçen switch yakalanır (self-review2).
                guard let current = state.userID else { continue }
                if let previous = lastUserID, previous != current {
                    self?.resetForAccountSwitch()
                }
                lastUserID = current
            }
        }
    }

    /// Feed hesap-özel durumunu sıfırlar: `.unlocked` işaretleri + A'nın seed'i temizlenir; uçuştaki seed
    /// resolution'ları `seedGeneration` bump'ıyla düşürülür; remount ile PlayerFeedView taze (boş) kurulur.
    private func resetForAccountSwitch() {
        seedGeneration &+= 1
        feedViewModel.feedState = FeedState()
        vipGrantedEpisodes = [] // feedState boşaldı → A'nın VIP-grant izleri B'ye taşınmaz
        feedEntry = nil
        pendingPlayback = nil
        activeEpisodeID = nil
        feedMountToken &+= 1
        // Self-review2: A'ya ait TÜM hesap-özel nav/sheet/devam-et yüzeyleri de temizlenmeli (DiziDetay push /
        // açık sheet / "devam et" banner'ı B'ye taşınmasın).
        path = []
        bolumListesiModel = nil
        speedMenuCurrentRate = nil
        subtitleChoices = nil
        continueEntry.reset()
        Task { [weak self] in await self?.continueEntry.load() } // B'nin devam-kaydını taze yükle
    }

    /// SwiftUI köprüsü — Ana Sayfa tab view'ı bunu gömer (delegate = self). `entry`: çözülmüş
    /// bağlamsal seed (nil → For You baştan). RootTabView `.id(feedMountToken)` ile yeni seed'de
    /// remount eder ki PlayerKit init-time seed'i taze `entry`'yi görsün.
    func makePlayerFeedView() -> PlayerFeedView {
        PlayerFeedView(
            viewModel: feedViewModel,
            playerPool: playerPool,
            prefetch: prefetch,
            // `decoratedAnalytics`: player-feed engagement event'leri (video_start/swipe_next/swipe_prev/
            // video_stall) `ab_variants` deney boyutunu TAŞIMALI (08 §7.3) — aksi halde en yüksek-trafikli
            // tüketim funnel'ı varyanta göre kırılamaz. BASE (`dependencies.analytics`) yerine decorated
            // (diğer TÜM feature wiring'i gibi); exposure BASE'de kalır (ayrı ExperimentClient yolu, §7.3).
            analytics: composition.decoratedAnalytics,
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
        case .arama, .ayarlar, .bildirimMerkezi:
            EmptyView() // Ana Sayfa stack'inde bu hedefler push edilmez (Profil stack'i).
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

    // MARK: - Hız menüsü (04 §8.2)

    /// Hız menüsünden seçim: kalıcı tercihi feed VM'ine yaz (köprü VC→director'a akıtır) + menüyü kapat.
    func selectPlaybackRate(_ rate: Double) {
        feedViewModel.preferredPlaybackRate = rate
        speedMenuCurrentRate = nil
    }

    /// Hız menüsü kapatıldı (seçim yapılmadan).
    func dismissSpeedMenu() {
        speedMenuCurrentRate = nil
    }

    // MARK: - Bağlamsal oynatma (SS-062 App feed dilimi tüketir)

    /// Sekme-kökü deep-link/push (`.home`) → Ana Sayfa stack'ini köke sıfırla (bayat DiziDetay'da
    /// kalınmaz; 02 §8.2). Tipli `[AppRoute]` (idempotent push için, FINDING 3) → sıfırlama koordinatörde kapsüllenir.
    func resetToRoot() {
        path = []
        // `.home` sekme-kökü hedefi bağlamsal oynatmayı da İPTAL eder: `.play`→`.home` ardışığında uçuştaki
        // `.play` seed'i (pendingPlayback + resolve Task) çözülüp feed'i o diziye remount ETMESİN → SON niyet
        // (.home kök) kazanır (yoksa erken `.play` kazanırdı). seedGeneration bump uçuştaki seed-resolution'ı
        // düşürür; pendingPlayback nil ise henüz-tüketilmemiş intent de temizlenir.
        pendingPlayback = nil
        seedGeneration &+= 1
    }

    func requestPlayback(_ intent: PlaybackIntent) {
        // PlayerFeed'i öne getir: DiziDetay/başka bir push altında GİZLİ kalmasın (02 §4.3.2). Ana
        // Sayfa stack'i köke sıfırlanır ki bağlamsal oynatma doğrudan feed'de görünsün.
        if !path.isEmpty {
            path = []
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

    func playerFeed(_: PlayerFeedViewController, didChangeActiveIndex _: Int, episode: Episode?) {
        // Aktif bölümü izle → BolumListesi "şu an" vurgusu (SS-062 sayfalama/heartbeat Faz 2'de).
        activeEpisodeID = episode?.id
    }

    func playerFeedDidRequestMoreItems(_: PlayerFeedViewController) {
        // TODO(SS-062): sonraki feed sayfası / yeni dizi önerisi yüklenip feedState'e eklenir.
    }

    func playerFeed(_: PlayerFeedViewController, didRequestSeriesDetail series: Series) {
        path.appendIfNotTop(.diziDetay(seriesID: series.id, source: .playerFeed))
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

    func playerFeed(_: PlayerFeedViewController, didRequestEpisodeList series: Series) {
        // BolumListesi sheet'i (04 §8.5): DiscoverKit modeli (katalog+entitlement) kurulur, aktif bölüm
        // vurgulanır; RootTabView `bolumListesiModel != nil` iken sunar. Seçim/kapama delegate'te temizler.
        bolumListesiModel = composition.makeBolumListesiModel(
            series: series,
            currentEpisodeID: activeEpisodeID,
            delegate: self
        )
    }

    func playerFeed(_: PlayerFeedViewController, didRequestPlaybackSpeedMenu currentRate: Double) {
        // Hız menüsü (04 §8.2): RootTabView `speedMenuCurrentRate != nil` iken action-sheet sunar;
        // güncel hız işaretli. Seçim `selectPlaybackRate` ile feedViewModel'e → VC → director'a akar.
        speedMenuCurrentRate = PlaybackSpeedMenu.selected(for: currentRate)
    }

    func playerFeed(_: PlayerFeedViewController, didRequestSubtitleMenu episode: Episode) {
        // Altyazı menüsü (04 §8.3 / SS-046): aktif dizinin sunduğu diller ∩ uygulama-offered + "Kapalı".
        // Dizi eşleşmezse/boşsa tüm offered listeye düşülür. Seçim `setSubtitleLanguage` → tercih değişir
        // → tüm slot backend'leri (SS-046) legible track'i canlı yeniden-seçer.
        let series = feedViewModel.feedState.items.first { $0.episode?.id == episode.id }?.series
        let offered = LanguageCatalog.offeredSubtitleLanguages
        let available = series?.localeInfo.subtitleLanguages ?? []
        // Menü ile TRACK SEÇİMİ aynı normalleştirmeden geçmeli (SubtitleTrackSelector primary-subtag
        // eşleştirir): exact `contains` "pt-BR" gibi region-kodlu sunucu track'ini gizlerdi (review bulgusu).
        let availableSubtags = Set(available.compactMap { SubtitleTrackSelector.primarySubtag($0) })
        let intersected = offered.filter { language in
            language.isOff || availableSubtags.contains(SubtitleTrackSelector.primarySubtag(language.code) ?? "")
        }
        subtitleChoices = intersected.count > 1 ? intersected : offered
    }

    func playerFeedDidCompleteEpisode(_: PlayerFeedViewController) {
        // Bölüm sonuna kadar izlendi = POZİTİF an → App Store puanlama istemini değerlendir (RTG-01;
        // kill-switch + terbiye/eşik composition/controller'da). Render-loop dışı (bölüm sonu olayı).
        composition.requestReviewIfEnabled(.episodeCompleted)
    }
}

// MARK: - Altyazı menüsü (04 §8.3 / SS-046)

extension HomeCoordinator {
    /// Menüden altyazı dili seçildi: tercihi yaz (persist + multicast → backend'ler canlı uygular) + kapat.
    func selectSubtitleLanguage(_ language: SubtitleLanguage) {
        _ = composition.languagePreferences.setSubtitleLanguage(language)
        subtitleChoices = nil
    }

    /// Altyazı menüsü kapatıldı (seçim yapılmadan).
    func dismissSubtitleMenu() {
        subtitleChoices = nil
    }

    /// Menüde işaretli göstermek için güncel altyazı tercihi (canlı okuma).
    var currentSubtitleLanguage: SubtitleLanguage {
        composition.languagePreferences.currentSubtitleLanguage
    }
}

// MARK: - BolumListesiDelegate (04 §8.5) — bölüm seçimi feed'e döner

extension HomeCoordinator: BolumListesiDelegate {
    func bolumListesiDidSelectEpisode(number: Int, in seriesID: SeriesID) {
        // Sheet'i kapat + feed'i seçilen bölüme geçir (mevcut bağlamsal oynatma yolu). Kilitliyse
        // feed o bölümde UnlockSheet'i açar (didReachLockedEpisode) — burada kilit kontrolü YOK.
        bolumListesiModel = nil
        requestPlayback(PlaybackIntent(seriesID: seriesID, episodeNumber: number))
    }

    func bolumListesiRequestsDismiss() {
        bolumListesiModel = nil
    }
}
