import AppFoundation
import DiscoverKit
import Foundation
import LibraryKit
import Observation
import SwiftUI

/// Listem koordinatörü (03 §3.1): `Listem` kökü + `DiziDetay` push + `PlayerFeed`'e bağlamsal geçiş.
/// `ListemDelegate` niyetlerini karşılar; oynatma/detay/paylaş/sekme geçişlerini üst koordinatöre
/// ve WalletFlow'a delege eder (R2 — LibraryKit PlayerKit/DiscoverKit'i import etmez).
@Observable
@MainActor
final class LibraryCoordinator {
    private let composition: AppComposition
    private let walletFlow: WalletFlowCoordinator
    weak var tabCoordinator: TabCoordinator?

    /// Listem stack'i — favori uzun-bas "Detaya Git" → DiziDetay push.
    var path: [AppRoute] = []

    /// Listem modeli — Favoriler/Devam Et servisleri + katalog JOIN. `lazy`: delegate = self.
    @ObservationIgnored private(set) lazy var listemModel: ListemModel =
        composition.makeListemModel(delegate: self)

    /// Hesap değişimi gözlemcisi — app ömrü boyunca canlı (Home/Rewards ile simetrik): switch hangi
    /// sekmede olursa olsun (Profil'den) yakalanır.
    @ObservationIgnored private var accountObserver: Task<Void, Never>?

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
        startObservingAccountSwitch()
    }

    /// Hesap DEĞİŞİMİNDE (userID farklı bir hesaba geçince) uzun-ömürlü `listemModel`'i sıfırlar — model
    /// TabCoordinator ömrü boyunca yaşar, switch'te yeniden yaratılmaz → cross-account state (A'nın favorileri/
    /// "devam et"/gizli-öğeleri) B'ye sızmasın (SS-132 sınıfı; Home/Rewards koordinatörleriyle simetrik). link
    /// (guest→AYNI userID) ve session-death/re-auth (nil-geçiş) reset TETİKLEMEZ; yalnız farklı-hesaba geçiş.
    private func startObservingAccountSwitch() {
        let session = composition.dependencies.session
        accountObserver = Task { [weak self] in
            var lastUserID: String?
            for await state in session.stateUpdates {
                // lastUserID YALNIZ non-nil'de güncellenir → nil-ara-durumdan (loggedOut) geçen switch yakalanır.
                guard let current = state.userID else { continue }
                if let previous = lastUserID, previous != current {
                    self?.listemModel.resetForAccountSwitch()
                    self?.path = [] // A'nın pushed DiziDetay'ı B'ye taşınmasın (HomeCoordinator simetriği)
                }
                lastUserID = current
            }
        }
    }

    /// Deep link / Profil "izleme geçmişi" → segment seçimi (02 §8.2 `mylist?segment=`).
    /// DiscoverKit segment tipini LibraryKit segmentine köprüler.
    func selectSegment(_ segment: DiscoverKit.MyListSegment?) {
        path = []
        guard let segment else { return }
        listemModel.selectSegment(mapped(segment))
    }

    private func mapped(_ segment: DiscoverKit.MyListSegment) -> LibraryKit.MyListSegment {
        switch segment {
        case .favorites: .favorites
        case .continueWatching: .continueWatching
        case .downloads: .downloads
        }
    }

    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case let .diziDetay(seriesID, source):
            DiziDetayView(model: composition.makeDiziDetayModel(seriesID: seriesID, source: source, delegate: tabCoordinator))
        case .arama, .ayarlar, .bildirimMerkezi:
            EmptyView() // Listem stack'inde bu hedefler push edilmez (Profil stack'i).
        }
    }
}

// MARK: - ListemDelegate (02 §4.12)

extension LibraryCoordinator: ListemDelegate {
    func listemPlaySeries(seriesID: SeriesID) {
        // Favori dokunuş → kaldığı yerden oynat (izlenmemişse baştan). Kaldığı yer çözümü burada.
        let service = composition.continueWatchingService
        Task { [weak self] in
            let record = try? await service.latestProgress(forSeries: seriesID)
            // Kayıt varsa TAM bölüm+konumdan (record.episodeID), yoksa dizinin ilk oynatılabilir
            // bölümünden baştan (episodeID nil → resolver ilk oynatılabilir bölümü seçer).
            self?.tabCoordinator?.requestPlayback(HomeCoordinator.PlaybackIntent(
                seriesID: seriesID,
                episodeID: record?.episodeID,
                startPositionSec: record?.positionSec ?? 0
            ))
        }
    }

    func listemResumeEpisode(seriesID: SeriesID, episodeID: EpisodeID, startPositionSec: Double) {
        // Devam Et kartı: bölüm ID'si doğrudan taşınır → seed tam bölüme çözülür (numara lookup'ı yok).
        tabCoordinator?.requestPlayback(HomeCoordinator.PlaybackIntent(
            seriesID: seriesID,
            episodeID: episodeID,
            startPositionSec: startPositionSec
        ))
    }

    func listemOpenDetail(seriesID: SeriesID) {
        path.appendIfNotTop(.diziDetay(seriesID: seriesID, source: .listem))
    }

    func listemShare(seriesID: SeriesID) {
        tabCoordinator?.sharePresenter.share(DeepLinkFactory.seriesURL(seriesID))
    }

    func listemRequestsDiscover() {
        tabCoordinator?.switchTab(.kesfet)
    }

    func listemRequestsHome() {
        tabCoordinator?.switchTab(.anaSayfa)
    }
}
