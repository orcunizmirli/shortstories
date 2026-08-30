extension FeedPlaybackDirector.SettleOutcome {
    /// İdempotent no-op mu (`.none`): `handleSettleOutcome` bunu `!isIdempotentNoOp` ile kullanır → bağımsız
    /// scroll-settle'ın `.none`'ı uçuştaki reaktivasyon guard'ını (reactivatingIndex) ERKEN temizlemesin
    /// (bulgu #2: lockedEpisodeID kalıcıyken sonraki apply İKİNCİ reaktivasyon dispatch eder → çift video_start).
    var isIdempotentNoOp: Bool {
        if case .none = self {
            true
        } else {
            false
        }
    }
}
