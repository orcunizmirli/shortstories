/// Buffer-stall durum makinesi (04 §6.x oynatma sağlığı). `AVPlayerBackend`'in stall bayrağı mantığını
/// saf/test-edilebilir bir value-type'a ayırır: KVO (`isPlaybackLikelyToKeepUp`) + NotificationCenter
/// (`playbackStalledNotification`) tarafı gerçek player'da kalır, KARAR mantığı burada deterministik
/// test edilir. Kurallar:
/// - `markStalled`: yalnız stall'a İLK girişte `true` döner → çift `stallBegan` emit edilmez.
/// - `markKeepUp(true)`: yalnız stall'dayken temizler → sahte `stallEnded` emit edilmez.
/// - `reset`: yeni yükleme VEYA `pause`'da çağrılır — oynatmıyorken "stall" durumu tutulmaz; böylece
///   duraklat-devam et sonrası sonraki GERÇEK stall bastırılmaz (audit LOW bug 70: bayrak yalnız
///   keepUp-true'da temizlendiğinden pause/resume arası takılı kalıp `playbackStalled`'ı yutuyordu).
struct StallTracker {
    private(set) var isStalled = false

    /// `playbackStalledNotification` geldi → `stallBegan` emit edilmeli mi?
    mutating func markStalled() -> Bool {
        guard !isStalled else { return false }
        isStalled = true
        return true
    }

    /// `isPlaybackLikelyToKeepUp` gözlemi → `stallEnded` emit edilmeli mi?
    mutating func markKeepUp(_ likelyToKeepUp: Bool) -> Bool {
        guard likelyToKeepUp, isStalled else { return false }
        isStalled = false
        return true
    }

    /// Yeni yükleme / duraklatma: stall durumu sıfırlanır.
    mutating func reset() {
        isStalled = false
    }
}
