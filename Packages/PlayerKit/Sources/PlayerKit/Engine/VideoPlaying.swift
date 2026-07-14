import AppFoundation
import Foundation

/// Buffer politikası değerleri (04 §4.1). Aktif player'da 0 = AVFoundation'ın
/// otomatik yönetimi; havuzdaki idle/warm player'da 1 sn — bandı işgal etmez.
struct BufferPolicy: Sendable, Equatable {
    let preferredForwardBufferSeconds: Double

    /// Oynayan player: sistem ileri buffer'ı ağa göre kendisi seçer.
    static let active = BufferPolicy(preferredForwardBufferSeconds: 0)
    /// Havuzda paused bekleyen player: en fazla ~1 sn ileri veri.
    static let idle = BufferPolicy(preferredForwardBufferSeconds: 1.0)
}

/// Player runtime'ından gelen teknoloji-bağımsız olaylar (PlayerKit-internal).
/// AVFoundation sinyalleri (`status`, stall bildirimi, DidPlayToEndTime) bu enum'a
/// çevrilir; testler sahte backend'le aynı olayları basar.
enum PlayerRuntimeEvent: Sendable, Equatable {
    case firstFrameReady
    case stallBegan
    case stallEnded
    case playedToEnd
    case didFail(AppError)
}

/// Jenerasyon korkuluğu (04 §14 T3/T4/T5 ailesinin async karşılığı): her runtime
/// olayı, ait olduğu YÜKLEMENİN jenerasyonuyla etiketlenir. `PlaybackEngine`
/// güncel jenerasyonla eşleşmeyen olayı sessizce düşürür — AsyncStream buffer'ında
/// bekleyen ya da KVO→Task köprüsünde geciken bayat sinyal yeni item'a uygulanmaz.
struct TaggedRuntimeEvent: Sendable, Equatable {
    let generation: UInt64
    let event: PlayerRuntimeEvent
}

/// AVPlayer sarmalayıcısının dar iç arayüzü (04 §2.4): AVFoundation'a dokunan tek
/// katman bu protokolün canlı uygulamasıdır (`AVPlayerBackend`); geri kalan her şey
/// (havuz, engine, testler) yalnız bu arayüzü görür.
protocol VideoPlaying: AnyObject, Sendable {
    /// Tek tüketicili olay akışı; tüketici `PlaybackEngine`'dir. Olaylar ait
    /// oldukları yüklemenin jenerasyonunu taşır (`TaggedRuntimeEvent`).
    var runtimeEvents: AsyncStream<TaggedRuntimeEvent> { get }

    /// `generation`: bu yüklemeden doğan tüm runtime olaylarına basılacak etiket;
    /// `PlaybackEngine.prepare`/`reset` her seferinde artırır (jenerasyon korkuluğu).
    func load(url: URL, bufferPolicy: BufferPolicy, generation: UInt64) async
    /// `playImmediately(atRate:)` karşılığı: buffer dolmasını beklemeden ilk kare (04 §4.2).
    func playImmediately(atRate rate: Double) async
    func pause() async
    /// Toleranslı/keskin seek ayrımı (04 §8.1 jest tablosu): `tolerant == true`
    /// çift-tap ±10 sn için hızlı segment-sınırı seek'idir; `tolerant == false`
    /// (`toleranceBefore/After = .zero`) YALNIZ scrubber bırakışına aittir.
    func seek(toSeconds seconds: Double, tolerant: Bool) async
    func setRate(_ rate: Double) async
    /// Aktif player'ı susturur/açar (02 §4.3.7 kabul kriteri): kilitli bölüme
    /// kaydırmada önceki player mute+pause garanti — pause'un tamamlanma yarışında
    /// ses sızıntısı penceresi kapanır.
    func setMuted(_ muted: Bool) async
    /// 2x uzun-basma / hız menüsü sırasında ses tonunu korur (04 §8.1, 01 PLR-03):
    /// `enabled == true` → `AVAudioTimePitchAlgorithm.timeDomain`; `false` → varispeed.
    func setPitchPreservation(_ enabled: Bool) async
    /// Item üzerinde buffer ayarını YERİNDE günceller; yeni item yaratmaz (04 §4.1).
    func applyBufferPolicy(_ policy: BufferPolicy) async
    /// Bitrate tavanı (04 §6.3, `preferredPeakBitRate` karşılığı): nil = tavansız
    /// (ABR karar verir). Değer sonraki item yüklemelerinde de korunur.
    func setPeakBitRateCap(_ bitsPerSecond: Double?) async
    func currentPositionSeconds() async -> Double
    /// `replaceCurrentItem(with: nil)` karşılığı: item gider, player kalır (04 §3.3).
    func clearItem() async
}

extension VideoPlaying {
    /// Keskin seek kısayolu (`.zero` tolerans): resume/scrubber bırakışı yolu.
    /// Çift-tap toleranslı seek `seek(toSeconds:tolerant:)`'i doğrudan çağırır.
    func seek(toSeconds seconds: Double) async {
        await seek(toSeconds: seconds, tolerant: false)
    }
}
