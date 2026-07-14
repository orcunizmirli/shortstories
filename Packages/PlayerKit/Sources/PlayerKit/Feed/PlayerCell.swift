import AppFoundation
import ContentKit
import DesignSystem
import SwiftUI
import UIKit

/// Tam ekran feed hücresi (PlayerKit-internal, SS-044): `PlayerLayerView` host'u,
/// poster placeholder, SwiftUI overlay (UIHostingConfiguration — 04 §8) ve jest
/// tanıyıcıları. Hücre İNCEDİR: jest kararları `FeedTapInterpreter`'da (saf),
/// oynatma koreografisi `FeedPlaybackDirector`'dadır; hücre yalnız sinyal taşır.
@MainActor
final class PlayerCell: UICollectionViewCell {
    static let reuseIdentifier = "PlayerCell"

    /// Sağ ray / overlay intent'leri (02 §4.3.2): feed VC delegate'e çevirir.
    enum OverlayIntent: Sendable {
        case seriesDetail
        case favorite
        case share
        case episodeList
        case speed
        case subtitles
        case unlock
    }

    var onTap: ((_ normalizedX: Double) -> Void)?
    var onLongPress: ((_ isPressed: Bool) -> Void)?
    var onFirstFrame: ((EpisodeID) -> Void)?
    var onOverlayIntent: ((OverlayIntent) -> Void)?

    private let layerView = PlayerLayerView()
    private let posterView = UIImageView()
    private var overlayHost: (UIView & UIContentView)?
    private var posterTask: Task<Void, Never>?
    private(set) var boundEpisodeID: EpisodeID?

    /// Poster→video geçiş animasyonunun süresi (04 §8 çapraz-geçiş).
    private static let revealAnimationDurationSeconds: Double = 0.15

    /// Reveal jenerasyonu (bulgu 3/7): her poster→video geçişi +1; unbind/reconfigure/
    /// prepareForReuse bunu artırır → uçuştaki animasyonun BAYAT completion'ı yeniden
    /// kullanılan/yeniden yapılandırılan hücrenin (başka item'ın) posterini gizleyemez.
    private(set) var revealGeneration: UInt64 = 0

    /// Test gözlemi (PlayerKit-internal): posterin gizli olup olmadığı.
    var posterIsHidden: Bool {
        posterView.isHidden
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureGestures()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    // MARK: - Yapılandırma

    /// Hücre içeriğini uygular. Aktif OYNAYAN hücrenin YERİNDE reconfigure'ünde (aynı
    /// bölüm hâlâ layer'a bağlı) canlı video opak posterle GÖMÜLMEZ: layer/first-frame
    /// durumu korunur, yalnız overlay tazelenir (bulgu 1/5). Bölüm farklıysa ya da
    /// bağlı değilse temiz poster reset'i (yeni bind willDisplay/settle yolundan gelir).
    func configure(with item: FeedItem) {
        let incomingEpisodeID = item.episode?.id
        let isReconfiguringBoundEpisode = incomingEpisodeID != nil
            && incomingEpisodeID == boundEpisodeID
            && layerView.isBoundToPlayer
        if !isReconfiguringBoundEpisode {
            invalidateReveal()
            boundEpisodeID = nil
            posterView.isHidden = false
            posterView.alpha = 1
            loadPoster(from: item.episode?.thumbnailURL ?? item.series.coverURL)
        }
        applyOverlay(for: item)
    }

    /// Aktif lease bağlama (04 §3.3 kural 4): layer bağlama willDisplay/settle
    /// yolunda lease üzerinden yapılır; ilk kare sinyali TTFF ölçümüne ve
    /// poster→video geçişine akar.
    func bind(handle: PlaybackHandle) {
        guard let source = handle.engine.backend as? AVPlayerSurfaceSource,
              let player = source.surfacePlayer
        else { return }
        let episodeID = handle.episodeID
        boundEpisodeID = episodeID
        layerView.onFirstFrameReady = { [weak self] in
            guard let self else { return }
            revealVideoSurface()
            onFirstFrame?(episodeID)
        }
        layerView.bind(player: player)
    }

    func unbind() {
        // Uçuştaki reveal iptal (bulgu 3/7): bayat completion bu hücreye dokunamaz.
        invalidateReveal()
        layerView.onFirstFrameReady = nil
        layerView.unbind()
        boundEpisodeID = nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        posterTask?.cancel()
        posterTask = nil
        // T8: yalnız layer bağlantısı çözülür (havuz slot'una DOKUNULMAZ) + reveal iptal.
        unbind()
        posterView.image = nil
        posterView.isHidden = false
        posterView.alpha = 1
    }

    // MARK: - Kurulum

    private func configureHierarchy() {
        contentView.backgroundColor = UIColor(DSColors.background)
        for subview in [layerView, posterView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: contentView.topAnchor),
                subview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                subview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
        }
        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
    }

    private func configureGestures() {
        // 04 §8: çift-tap tanıyıcı ve require(toFail:) KULLANILMAZ — 250 ms bekleme
        // yok. Her tap anında FeedTapInterpreter'a (feed VC) akar.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tap.delegate = self
        contentView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture(_:)))
        // 01 PLR-03: eşik 400 ms (UIKit varsayılanı 0.5 s değil).
        longPress.minimumPressDuration = FeedHoldSpeedPolicy.minimumPressDurationSeconds
        // Dikey kaydırma başlarsa 2x iptal: parmak `allowableMovement` eşiğini geçince
        // uzun basma .cancelled olur (→ onLongPress(false)) ve paging pan devralır.
        // Collection view'ın pan'iyle EŞ ZAMANLI tanınmaz (varsayılan) — jest önceliği.
        longPress.delegate = self
        contentView.addGestureRecognizer(longPress)
    }

    // MARK: - Jest işleyicileri

    @objc private func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        let width = max(contentView.bounds.width, 1)
        let normalizedX = recognizer.location(in: contentView).x / width
        onTap?(Double(normalizedX))
    }

    @objc private func handleLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onLongPress?(true)
        case .ended, .cancelled, .failed:
            onLongPress?(false)
        case .possible, .changed:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Poster placeholder → video geçişi

    private func loadPoster(from url: URL) {
        posterTask?.cancel()
        posterTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = UIImage(data: data)
            else { return }
            self?.posterView.image = image
        }
    }

    /// İlk kare geldi: poster videoya çapraz-geçer. Geçiş, doğduğu reveal jenerasyonunu
    /// taşır — completion YALNIZ animasyon doğal bittiyse VE jenerasyon hâlâ güncelse
    /// posteri gizler (bulgu 3/7). PlayerKit-internal (test bu yolu deterministik sürer).
    func revealVideoSurface() {
        revealGeneration &+= 1
        let generation = revealGeneration
        posterView.isHidden = false
        UIView.animate(withDuration: Self.revealAnimationDurationSeconds) {
            self.posterView.alpha = 0
        } completion: { [weak self] finished in
            self?.finishRevealIfCurrent(generation: generation, finished: finished)
        }
    }

    /// Reveal completion korkuluğu (bulgu 3/7): bayat/iptal edilmiş geçişin completion'ı
    /// başka item'ın posterini gizleyemez — `finished` + güncel jenerasyon şart.
    func finishRevealIfCurrent(generation: UInt64, finished: Bool) {
        guard finished, generation == revealGeneration else { return }
        posterView.isHidden = true
    }

    /// Uçuştaki reveal'i geçersizler: jenerasyon +1 (bekleyen completion düşer) ve
    /// poster katmanındaki explicit animasyon kaldırılır.
    private func invalidateReveal() {
        revealGeneration &+= 1
        posterView.layer.removeAllAnimations()
    }

    // MARK: - Overlay (SwiftUI — UIHostingConfiguration, 04 §8)

    private func applyOverlay(for item: FeedItem) {
        let isLocked = item.episode.map { !$0.access.isPlayableWithoutUnlock } ?? false
        let content = PlayerOverlayContent(
            seriesTitle: item.series.title,
            episodeLabel: episodeLabel(for: item),
            initialProgress: initialProgress(for: item),
            lockState: isLocked ? PlayerOverlayContent.LockState(priceLabel: priceLabel(for: item)) : nil,
            actions: PlayerOverlayContent.Actions(
                seriesDetail: { [weak self] in self?.onOverlayIntent?(.seriesDetail) },
                favorite: { [weak self] in self?.onOverlayIntent?(.favorite) },
                share: { [weak self] in self?.onOverlayIntent?(.share) },
                episodeList: { [weak self] in self?.onOverlayIntent?(.episodeList) },
                speed: { [weak self] in self?.onOverlayIntent?(.speed) },
                subtitles: { [weak self] in self?.onOverlayIntent?(.subtitles) },
                unlock: { [weak self] in self?.onOverlayIntent?(.unlock) }
            )
        )
        let configuration = UIHostingConfiguration { content }.margins(.all, 0)
        if let overlayHost {
            overlayHost.configuration = configuration
        } else {
            let host = configuration.makeContentView()
            host.translatesAutoresizingMaskIntoConstraints = false
            host.backgroundColor = .clear
            contentView.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: contentView.topAnchor),
                host.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
            overlayHost = host
        }
    }

    private func episodeLabel(for item: FeedItem) -> String {
        guard let episode = item.episode else { return item.series.title }
        return "Bölüm \(episode.index) / \(item.series.episodeCount)"
    }

    private func initialProgress(for item: FeedItem) -> Double {
        guard let progress = item.progress, progress.durationSec > 0 else { return 0 }
        return progress.positionSec / progress.durationSec
    }

    private func priceLabel(for item: FeedItem) -> String? {
        guard let episode = item.episode, let price = episode.access.unlockPrice else { return nil }
        return "\(price) coin"
    }
}

// MARK: - Jest/overlay çakışma çözümü

extension PlayerCell: UIGestureRecognizerDelegate {
    /// Overlay'in etkileşimli SwiftUI öğesine (ray butonu, Kilidi Aç) düşen dokunuş
    /// video jestlerine GİTMEZ; boş overlay bölgeleri jest katmanına akar
    /// (02 §4.3.2 katman z-sırası).
    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let overlayHost, let touchedView = touch.view else { return true }
        if touchedView === overlayHost {
            return true
        }
        return !touchedView.isDescendant(of: overlayHost)
    }
}
