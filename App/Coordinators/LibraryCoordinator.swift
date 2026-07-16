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
    var path = NavigationPath()

    /// Listem modeli — Favoriler/Devam Et servisleri + katalog JOIN. `lazy`: delegate = self.
    @ObservationIgnored private(set) lazy var listemModel: ListemModel =
        composition.makeListemModel(delegate: self)

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
    }

    /// Deep link / Profil "izleme geçmişi" → segment seçimi (02 §8.2 `mylist?segment=`).
    /// DiscoverKit segment tipini LibraryKit segmentine köprüler.
    func selectSegment(_ segment: DiscoverKit.MyListSegment?) {
        path = NavigationPath()
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
        case .arama, .ayarlar:
            EmptyView() // Listem stack'inde bu hedefler push edilmez.
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
            self?.tabCoordinator?.requestPlayback(HomeCoordinator.PlaybackIntent(
                seriesID: seriesID,
                episodeNumber: nil,
                startPositionSec: record?.positionSec ?? 0
            ))
        }
    }

    func listemResumeEpisode(seriesID: SeriesID, episodeID _: EpisodeID, startPositionSec: Double) {
        tabCoordinator?.requestPlayback(HomeCoordinator.PlaybackIntent(
            seriesID: seriesID,
            episodeNumber: nil,
            startPositionSec: startPositionSec
        ))
    }

    func listemOpenDetail(seriesID: SeriesID) {
        path.append(AppRoute.diziDetay(seriesID: seriesID, source: .listem))
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
