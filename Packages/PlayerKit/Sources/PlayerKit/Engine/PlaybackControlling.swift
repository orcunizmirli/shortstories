import AppFoundation
import Foundation

/// Aktif oynatmanın public kontrol yüzeyi (04 §2.4 modül sınırı): yalnız value
/// tipleri + `AsyncStream`; imzalarda AVFoundation tipi YOKTUR. Player teknolojisi
/// değişse de bu sözleşme değişmez (KANON §2).
public protocol PlaybackControlling: Sendable {
    /// Kontrol edilen bölümün kimliği.
    var episodeID: EpisodeID { get }

    /// Oynatmayı başlatır/sürdürür. Motor hâlâ yüklüyorsa niyet kuyruklanır ve ilk
    /// karede beklemeden uygulanır (04 §4.2 playImmediately semantiği).
    func play() async

    /// Oynatmayı duraklatır.
    func pause() async

    /// Verilen saniyeye konumlanır.
    func seek(toSeconds seconds: Double) async

    /// Oynatma hızını ayarlar (hız menüsü 0.75x–2x; 04 §8.2).
    func setRate(_ rate: Double) async

    /// Anlık motor durumu.
    func currentState() async -> PlayerEngineState

    /// Durum akışı: abone ilk değer olarak son bilinen durumu alır, sonra her
    /// geçişte yeni durumu (Combine yasak — 03 §7; AsyncStream kanonu).
    func statusUpdates() async -> AsyncStream<PlayerEngineState>
}

/// Havuzdan kiralanan oynatmanın value-tipi tutamacı. `PlayerPool.activate`
/// döndürür; feed katmanı yalnız bu tutamaç üzerinden oynatmayı sürer.
/// Player instance'ının sahibi HAVUZDUR (04 §3.3); tutamaç sahiplik taşımaz.
public struct PlaybackHandle: PlaybackControlling {
    public let episodeID: EpisodeID
    let engine: PlaybackEngine

    public func play() async {
        await engine.play()
    }

    public func pause() async {
        await engine.pause()
    }

    public func seek(toSeconds seconds: Double) async {
        await engine.seek(toSeconds: seconds)
    }

    public func setRate(_ rate: Double) async {
        await engine.setRate(rate)
    }

    public func currentState() async -> PlayerEngineState {
        await engine.currentState()
    }

    public func statusUpdates() async -> AsyncStream<PlayerEngineState> {
        await engine.statusUpdates()
    }
}
