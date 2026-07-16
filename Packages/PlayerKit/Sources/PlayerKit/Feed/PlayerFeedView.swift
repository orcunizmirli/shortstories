import AppFoundation
import SwiftUI

/// SwiftUI köprüsü (04 §2.3): Ana Sayfa sekmesinin feed'e TEK giriş noktası.
/// `playerPool`/`prefetch` kompozisyon kökünde (ShortSeriesApp) kurulur ve
/// init-injection ile gelir — `Dependencies` konteynerine KONMAZ (04 §2.4 kural 2).
/// `delegate` App katmanındaki Coordinator'dır; sahipliği Coordinator'ın kendisi
/// taşır (VC yalnız weak tutar).
public struct PlayerFeedView: UIViewControllerRepresentable {
    private let viewModel: PlayerFeedViewModel
    private let playerPool: PlayerPool
    private let prefetch: PrefetchController
    private let analytics: any AnalyticsTracking
    private let entry: FeedEntry?
    private weak var delegate: (any PlayerFeedDelegate)?

    /// `entry`: feed-entry/seed (SS-062/065) — feed'i belirli bir dizi/bölüm ve konumdan
    /// başlatır ("kaldığın yerden devam"). nil (varsayılan) ise For You akışı baştan açılır;
    /// mevcut çağrılar bu varsayılanla değişmeden çalışır (geriye-uyumlu genişletme, 04 §2.4).
    public init(
        viewModel: PlayerFeedViewModel,
        playerPool: PlayerPool,
        prefetch: PrefetchController,
        analytics: any AnalyticsTracking,
        delegate: (any PlayerFeedDelegate)? = nil,
        entry: FeedEntry? = nil
    ) {
        self.viewModel = viewModel
        self.playerPool = playerPool
        self.prefetch = prefetch
        self.analytics = analytics
        self.delegate = delegate
        self.entry = entry
    }

    public func makeUIViewController(context _: Context) -> PlayerFeedViewController {
        let controller = PlayerFeedViewController(
            viewModel: viewModel,
            playerPool: playerPool,
            prefetch: prefetch,
            analytics: analytics,
            entry: entry
        )
        controller.delegate = delegate
        return controller
    }

    public func updateUIViewController(_ controller: PlayerFeedViewController, context _: Context) {
        controller.delegate = delegate
        controller.apply(state: viewModel.feedState) // diff'li uygulama; reloadData YASAK (04 §14 T7)
    }
}
