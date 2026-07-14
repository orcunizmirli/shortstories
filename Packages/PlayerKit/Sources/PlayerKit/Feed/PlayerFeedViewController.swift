import AppFoundation
import ContentKit
import DesignSystem
import UIKit

/// Dikey tam ekran player feed'i (04 §2, SS-044): `UICollectionView` paging + diffable.
/// UIKit katmanı İNCEDİR — jest kararları `FeedTapInterpreter`'da, koreografi
/// `FeedPlaybackDirector` actor'ünde serileşir. Public yüzey kapalı listedir (04 §2.4):
/// `init + apply(state:) + delegate`; scroll delegate'i internal `FeedScrollProxy`'dedir —
/// scroll/willDisplay metotları public SIZMAZ. Niyetler `PlayerFeedDelegate` ile akar (04 §2.2).
public final class PlayerFeedViewController: UIViewController {
    /// Coordinator bağlaması (App katmanı — 03 mimarisi).
    public weak var delegate: (any PlayerFeedDelegate)?

    private let viewModel: PlayerFeedViewModel
    let director: FeedPlaybackDirector

    private(set) var items: [FeedItem] = []
    private var itemsByID: [String: FeedItem] = [:]
    private(set) var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<FeedSection, String>?
    private var tapInterpreter = FeedTapInterpreter()
    private var autoAdvanceTask: Task<Void, Never>?
    private var needsInitialActivation = true
    /// Public scroll-delegate metotlarını VC yüzeyinden ayıran internal proxy (04 §2.4).
    private let scrollProxy = FeedScrollProxy()
    /// Programatik kaydırma (auto-advance) yerleşince uygulanacak settle.
    var pendingProgrammaticSettle: (index: Int, startType: PlaybackStartType)?
    /// Settle sonucu geldiğinde hücre henüz görünür değilse bağlama willDisplay'e kalır.
    var pendingBind: (index: Int, handle: PlaybackHandle)?
    /// Son settle'da kilitli kalan indeks (04 §9.2 / 02 §4.3.6): unlock sonrası aynı
    /// kartta oynatmayı yeniden başlatmak için `apply(state:)` bunu tetikler.
    private var lockedIndex: Int?
    /// Hız menüsü intent'ine taşınan oturum tercihi (04 §8.2; kalıcılaştırma SS-131).
    private var currentPreferredRate = 1.0

    private enum FeedSection: Hashable {
        case main
    }

    /// Kompozisyon kökü init'i (04 §2.3): havuz/prefetch `Dependencies`'e KONMAZ,
    /// init-injection ile gelir (04 §2.4 kural 2); `analytics` type-erased porttur (03 §5.1).
    public init(
        viewModel: PlayerFeedViewModel,
        playerPool: PlayerPool,
        prefetch: PrefetchController,
        analytics: any AnalyticsTracking
    ) {
        self.viewModel = viewModel
        director = FeedPlaybackDirector(
            pool: playerPool,
            prefetch: prefetch,
            metrics: PlayerMetricsCollector(analytics: analytics),
            poolSizeProvider: { await playerPool.slotCount }
        )
        super.init(nibName: nil, bundle: nil)
        scrollProxy.controller = self
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        nil
    }

    deinit {
        autoAdvanceTask?.cancel()
        // Feed'den çıkış (04 §3.3): item'lar bırakılır, player'lar korunur.
        Task { [director] in
            await director.teardown()
        }
    }

    // MARK: - Yaşam döngüsü

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(DSColors.background)
        configureCollectionView()
        startAutoAdvanceConsumer()
        if items.isEmpty {
            apply(state: viewModel.feedState)
        } else {
            // apply(state:) görünüm yüklenmeden çağrıldı: snapshot + ilk aktivasyon şimdi.
            renderSnapshot()
            activateFirstIfNeeded()
        }
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let collectionView,
              let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
              collectionView.bounds.size != .zero,
              layout.itemSize != collectionView.bounds.size
        else { return }
        layout.itemSize = collectionView.bounds.size
        layout.invalidateLayout()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Sekme değişimi pause kuralı (04 §10.4/11); audio session bırakma App'te (SS-049/061).
        Task { [director] in
            await director.pauseActive()
        }
    }

    // MARK: - Public yüzey

    /// Feed durumunu diff'li uygular (04 §2.3): `reloadData` YASAK (T7). Aynı id ile
    /// içeriği değişen hücreler reconfigure edilir (02 §4.3.6); kilitli kart unlock
    /// olduysa aynı hücrede yeniden aktive edilir (04 §9.2).
    public func apply(state: FeedState) {
        let newItems = state.items.deduplicatingEpisodes()
        guard newItems != items else { return }
        let previousItems = items
        items = newItems
        itemsByID = Dictionary(newItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        renderSnapshot(previousItems: previousItems)

        let shouldActivateFirst = needsInitialActivation && !newItems.isEmpty && isViewLoaded
        if shouldActivateFirst {
            needsInitialActivation = false
        }
        let reactivateIndex = shouldActivateFirst ? nil : reactivatableUnlockIndex(in: newItems)
        Task { [weak self, director] in
            await director.updateItems(newItems)
            guard let self else { return }
            if shouldActivateFirst {
                // İlk açılış: doğrudan video ile başlar (02 §4.3); devam kaydı varsa resume.
                await performSettle(at: 0, startType: .tap)
            } else if let reactivateIndex {
                // 04 §9.2 / 02 §4.3.6: kilit açıldı, kart yerinde oynatmaya başlar.
                let outcome = await self.director.reactivateAfterUnlock(at: reactivateIndex, now: Date())
                handleSettleOutcome(outcome, at: reactivateIndex)
            }
        }
    }

    /// Kilitli kalan aktif kart yeni state'te oynatılabilir olduysa indeksi döner (arka
    /// planda / sheet sonrası unlock — access `.locked` → oynatılabilir). Saf entitlement
    /// sinyali (access.kind değişmeden) WalletKit `episodeUnlocked` portundadır — SS-050.
    private func reactivatableUnlockIndex(in newItems: [FeedItem]) -> Int? {
        guard let lockedIndex, newItems.indices.contains(lockedIndex),
              newItems[lockedIndex].episode?.access.isPlayableWithoutUnlock == true
        else { return nil }
        return lockedIndex
    }

    private func renderSnapshot(previousItems: [FeedItem] = []) {
        guard let dataSource else { return } // görünüm yüklenince viewDidLoad basar
        var snapshot = NSDiffableDataSourceSnapshot<FeedSection, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items.map(\.id))
        // Aynı id ile içeriği değişen hücreler yerinde reconfigure (02 §4.3.6; T7 ihlali yok).
        let previousByID = Dictionary(previousItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changedIDs = items.compactMap { item -> String? in
            guard let old = previousByID[item.id], old != item else { return nil }
            return item.id
        }
        if !changedIDs.isEmpty {
            snapshot.reconfigureItems(changedIDs)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func activateFirstIfNeeded() {
        guard needsInitialActivation, !items.isEmpty else { return }
        needsInitialActivation = false
        let snapshotItems = items
        Task { [weak self, director] in
            // İlk aktivasyon yarışı (denetim): updateItems'ın settle'dan ÖNCE koştuğunu
            // garanti eder — settle boş items görüp .none dönemez (02 §5.1 ilk video < 3 sn).
            await director.updateItems(snapshotItems)
            await self?.performSettle(at: 0, startType: .tap)
        }
    }

    // MARK: - Collection view kurulumu

    private func configureCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.isPagingEnabled = true // tam ekran kart, tek seferde tek kart (02 §4.3.1)
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = UIColor(DSColors.background)
        collectionView.delegate = scrollProxy
        view.addSubview(collectionView)
        self.collectionView = collectionView

        let registration = UICollectionView.CellRegistration<PlayerCell, String> { [weak self] cell, _, itemID in
            guard let self, let item = itemsByID[itemID] else { return }
            configure(cell: cell, with: item)
        }
        dataSource = UICollectionViewDiffableDataSource<FeedSection, String>(
            collectionView: collectionView
        ) { collectionView, indexPath, itemID in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemID)
        }
    }

    private func configure(cell: PlayerCell, with item: FeedItem) {
        cell.configure(with: item)
        cell.onTap = { [weak self] normalizedX in
            self?.handleTap(normalizedX: normalizedX)
        }
        cell.onLongPress = { [weak self] isPressed in
            guard let director = self?.director else { return }
            Task { await director.setHoldSpeed(isPressed) }
        }
        cell.onFirstFrame = { [weak self] episodeID in
            guard let director = self?.director else { return }
            let now = Date()
            Task { await director.firstFrameBecameVisible(episodeID: episodeID, at: now) }
        }
        cell.onOverlayIntent = { [weak self] intent in
            self?.handleOverlayIntent(intent, itemID: item.id)
        }
    }

    // MARK: - Settle akışı (kaydırma yerleşti → aktif kart)

    func settle(at index: Int, startType: PlaybackStartType) {
        Task { [weak self] in
            await self?.performSettle(at: index, startType: startType)
        }
    }

    private func performSettle(at index: Int, startType: PlaybackStartType) async {
        let outcome = await director.settle(at: index, startType: startType, now: Date())
        handleSettleOutcome(outcome, at: index)
    }

    private func handleSettleOutcome(_ outcome: FeedPlaybackDirector.SettleOutcome, at index: Int) {
        switch outcome {
        case let .activated(handle, episode):
            if lockedIndex == index {
                lockedIndex = nil
            }
            bindCellIfVisible(handle: handle, at: index)
            delegate?.playerFeed(self, didChangeActiveIndex: index, episode: episode)
        case let .locked(episode):
            // Kart kilit durumunu zaten gösterir (02 §4.3.5); UnlockSheet intent'i Coordinator'a.
            lockedIndex = index
            pendingBind = nil
            delegate?.playerFeed(self, didChangeActiveIndex: index, episode: episode)
            if let series = itemAt(index)?.series {
                delegate?.playerFeed(self, didReachLockedEpisode: episode, in: series)
            }
        case .settledWithoutEpisode:
            // Bölüm taşımayan kart (seriesPromo / dizi-sonu ara kartı): aktif indeks
            // değişti, bölüm nil (04 §2.4 PlayerFeedDelegate sözleşmesi).
            pendingBind = nil
            lockedIndex = nil
            delegate?.playerFeed(self, didChangeActiveIndex: index, episode: nil)
        case .failed:
            // SS-051 dilimi: sınıflandırılmış hata UI'ı (toast + tekrar dene). Hücre posterde kalır.
            pendingBind = nil
        case .none:
            break
        }
    }

    private func bindCellIfVisible(handle: PlaybackHandle, at index: Int) {
        pendingBind = nil
        let indexPath = IndexPath(item: index, section: 0)
        guard let cell = collectionView?.cellForItem(at: indexPath) as? PlayerCell else {
            pendingBind = (index, handle) // hücre henüz görünür değil: willDisplay bağlar
            return
        }
        cell.bind(handle: handle)
    }

    private func itemAt(_ index: Int) -> FeedItem? {
        items.indices.contains(index) ? items[index] : nil
    }
}

// MARK: - Jest köprüsü (kararlar saf yorumlayıcıda)

extension PlayerFeedViewController {
    private func handleTap(normalizedX: Double) {
        let action = tapInterpreter.handleTap(normalizedX: normalizedX, at: Date())
        Task { [director] in
            switch action {
            case .togglePlayPause:
                await director.togglePlayPause()
            case let .revertToggleAndSeek(offsetSeconds):
                await director.revertToggleAndSeek(offsetSeconds: offsetSeconds)
            case let .seek(offsetSeconds):
                await director.seekByOffset(offsetSeconds)
            }
        }
    }

    private func handleOverlayIntent(_ intent: PlayerCell.OverlayIntent, itemID: String) {
        guard let item = itemsByID[itemID] else { return }
        switch intent {
        case .seriesDetail:
            delegate?.playerFeed(self, didRequestSeriesDetail: item.series)
        case .favorite:
            delegate?.playerFeed(self, didRequestFavoriteToggle: item.series, episode: item.episode)
        case .share:
            delegate?.playerFeed(self, didRequestShare: item.series, episode: item.episode)
        case .episodeList:
            delegate?.playerFeed(self, didRequestEpisodeList: item.series)
        case .speed:
            delegate?.playerFeed(self, didRequestPlaybackSpeedMenu: currentPreferredRate)
        case .subtitles:
            if let episode = item.episode {
                delegate?.playerFeed(self, didRequestSubtitleMenu: episode)
            }
        case .unlock:
            if let episode = item.episode {
                delegate?.playerFeed(self, didReachLockedEpisode: episode, in: item.series)
            }
        }
    }
}

// MARK: - Auto-advance tüketimi (04 §8.6)

extension PlayerFeedViewController {
    private func startAutoAdvanceConsumer() {
        let decisions = director.autoAdvanceDecisions
        autoAdvanceTask = Task { [weak self] in
            for await decision in decisions {
                guard let self else { return }
                execute(decision)
            }
        }
    }

    private func execute(_ decision: AutoAdvancePolicy.Decision) {
        switch decision {
        case let .advance(toIndex):
            guard items.indices.contains(toIndex) else { return }
            pendingProgrammaticSettle = (toIndex, .autoAdvance)
            collectionView?.scrollToItem(
                at: IndexPath(item: toIndex, section: 0),
                at: .centeredVertically,
                animated: true // kısa geçiş animasyonu (04 §8.6)
            )
        case .requestMoreItems:
            delegate?.playerFeedDidRequestMoreItems(self)
        case .stay:
            // Otomatik oynatma kapalı: bölüm sonu kartı SS-062'nin sonraki dilimi.
            break
        }
    }
}
