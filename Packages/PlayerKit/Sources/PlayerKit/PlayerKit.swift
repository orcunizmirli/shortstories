import AnalyticsKit
import AppFoundation
import ContentKit
import DesignSystem

/// PlayerKit — PlayerPool (actor), PrefetchController, PlayerFeedViewController ve oynatma UI'ı (KANON §4).
/// F1 kapsamı: SS-040…SS-052 (docs/09 §E5) + feed ilerleme/overlay kalemleri SS-062, SS-063,
/// SS-065, SS-066 (§E6). Davranış spesifikasyonu 04-player-engine.md'dedir.
/// AVFoundation tipleri public API'ye sızmaz (KANON §2 player teknolojisi sınırı).
public enum PlayerKitModule {
    public static let name = "PlayerKit"
}
