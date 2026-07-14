import AppFoundation

/// Oynatma motorunun dışa görünen durumu (04 §2.4 modül sınırı: AVFoundation tipi
/// içermez; player teknolojisi değişse de bu enum değişmez).
///
/// Akış: `idle → loading → readyAtFirstFrame → playing ⇄ paused`;
/// oynatma sırasında buffer beklemesi `stalled`, kurtarılamayan hata `failed`dır.
public enum PlayerEngineState: Sendable, Equatable {
    /// Slot boş; item bağlı değil (havuzda bekleyen player).
    case idle
    /// Asset/URL yükleniyor; kullanıcı yüzeyi spinner gösterebilir.
    case loading
    /// İlk video karesi hazır (TTFF işaret noktası, 08 §4 normatif tanım).
    case readyAtFirstFrame
    /// Oynuyor.
    case playing
    /// Kullanıcı veya sistem tarafından duraklatıldı.
    case paused
    /// Buffer kaynaklı bekleme (04 §13.1 stall tanımının durum karşılığı).
    case stalled
    /// Kurtarılamayan hata; taşınan hata tipi katman sınırı sözleşmesidir (03 §10.1).
    case failed(AppError)
}

/// Durum makinesini süren olaylar (PlayerKit-internal).
enum PlayerEngineEvent: Sendable, Equatable {
    case loadRequested
    case firstFrameReady
    case playRequested
    case pauseRequested
    case stallBegan
    case stallEnded
    /// İmzalı URL kurtarması başladı (04 §6.4): kullanıcı failed görmez, loading görür.
    case recoveryStarted
    case didFail(AppError)
    case resetRequested
}

/// Saf durum makinesi: geçiş tablosu test edilebilir, yan etkisiz.
/// Geçersiz geçişler yok sayılır (`nextState` nil döner, state korunur).
struct PlayerStateMachine: Sendable, Equatable {
    private(set) var state: PlayerEngineState

    init(state: PlayerEngineState = .idle) {
        self.state = state
    }

    /// Geçiş tablosu (04 §2 durumları): nil = geçersiz geçiş.
    static func nextState(from state: PlayerEngineState, on event: PlayerEngineEvent) -> PlayerEngineState? {
        switch event {
        case .resetRequested:
            resetTarget(from: state)
        case let .didFail(error):
            .failed(error)
        case .recoveryStarted:
            recoveryTarget(from: state)
        case .loadRequested:
            loadTarget(from: state)
        case .firstFrameReady:
            firstFrameTarget(from: state)
        case .playRequested:
            playTarget(from: state)
        case .pauseRequested:
            pauseTarget(from: state)
        case .stallBegan:
            stallBeganTarget(from: state)
        case .stallEnded:
            stallEndedTarget(from: state)
        }
    }

    private static func resetTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        state == .idle ? nil : .idle
    }

    private static func recoveryTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        switch state {
        case .loading, .readyAtFirstFrame, .playing, .paused, .stalled:
            .loading
        case .idle, .failed:
            nil
        }
    }

    private static func loadTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        switch state {
        case .idle, .failed:
            .loading
        default:
            nil
        }
    }

    private static func firstFrameTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        state == .loading ? .readyAtFirstFrame : nil
    }

    private static func playTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        switch state {
        case .readyAtFirstFrame, .paused:
            .playing
        default:
            nil
        }
    }

    private static func pauseTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        switch state {
        case .playing, .stalled, .readyAtFirstFrame:
            .paused
        default:
            nil
        }
    }

    private static func stallBeganTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        state == .playing ? .stalled : nil
    }

    private static func stallEndedTarget(from state: PlayerEngineState) -> PlayerEngineState? {
        state == .stalled ? .playing : nil
    }

    /// Olayı uygular; state değiştiyse `true` döner (yayın kararı çağırana aittir).
    @discardableResult
    mutating func handle(_ event: PlayerEngineEvent) -> Bool {
        guard let next = Self.nextState(from: state, on: event) else { return false }
        state = next
        return true
    }
}
