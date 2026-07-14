import AppFoundation

/// İmzalı URL / geçici CDN hatası kurtarma politikası — SAF (04 §6.4, SS-051 çekirdeği):
/// 410 `signedURLExpired` ve geçici medya hatası (`assetUnavailable`; CDN 403 bu tipe
/// eşlenir) 1 otomatik denemeyle taze URL'den kurtarılır; ikinci hata yüzeye çıkar
/// (hücre içi hata durumu + "Tekrar dene" — feed VC dilimi).
enum SignedURLRecoveryPolicy {
    enum Action: Sendable, Equatable {
        /// Konumu koru → taze imzalı URL → yeniden yükle → seek → playImmediately.
        case refreshAndResume
        /// Hata kullanıcı yüzeyine çıkar (state: `.failed`).
        case surface
    }

    /// Otomatik deneme tavanı (04 §6.4 kural 5: "1 otomatik deneme").
    static let maxAutomaticAttempts = 1

    static func action(for error: AppError, attempt: Int) -> Action {
        guard attempt < maxAutomaticAttempts else { return .surface }
        switch error {
        case .playback(.signedURLExpired), .playback(.assetUnavailable):
            return .refreshAndResume
        default:
            return .surface
        }
    }
}
