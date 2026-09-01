import Foundation

/// Derleme zamanı + kullanıcı ayarı bileşimi olarak özellik anahtarları.
///
/// Uzaktan yapılandırma **yoktur** (KANON §1: ağ yok). Bayraklar ya derlemeye gömülüdür ya da
/// kullanıcının Ayarlar'da açıp kapattığı tercihlerdir.
public struct FeatureFlags: Sendable, Equatable {
    /// Foundation Models yolu tamamen kapatılır; yalnız heuristik analiz çalışır.
    /// Kullanıcı tarafından Ayarlar > Zekâ modunu kapat ile değiştirilir.
    public var intelligenceEnabled: Bool
    /// Arka planda (`BGProcessingTask`) indekslemeye izin verilir.
    public var backgroundIndexingEnabled: Bool
    /// Yalnız cihaz şarjdayken analiz yapılır.
    public var indexOnlyWhileCharging: Bool
    /// Temizlik asistanı (P1) — varsayılan kapalı, Pro gerektirir.
    public var cleanupAssistantEnabled: Bool

    public init(
        intelligenceEnabled: Bool = true,
        backgroundIndexingEnabled: Bool = true,
        indexOnlyWhileCharging: Bool = false,
        cleanupAssistantEnabled: Bool = false
    ) {
        self.intelligenceEnabled = intelligenceEnabled
        self.backgroundIndexingEnabled = backgroundIndexingEnabled
        self.indexOnlyWhileCharging = indexOnlyWhileCharging
        self.cleanupAssistantEnabled = cleanupAssistantEnabled
    }

    public static let `default` = FeatureFlags()
}
