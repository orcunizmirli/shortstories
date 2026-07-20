import Foundation

/// Çözülen remote config'i tüketicilere (App wiring, A/B SS-154, WalletKit win-back,
/// RewardsKit ad-cap, force-update kapısı) sunan port (05 §4.10, 03 §11).
///
/// Okuma modeli freeze-per-launch'a tabidir (03 §11): `refresh()` flag snapshot'ını
/// bir SONRAKİ launch için yazar; canlı flag okuma yüzeyi `FeatureFlagStore`'dur.
/// `cachedConfig()` ise senkron son-bilinen config'i (sürüm/ürün/atama okuması) verir.
public protocol RemoteConfigProviding: Sendable {
    /// Cache'teki son config — TAZE veya BAYAT olabilir; hiç cache yoksa `nil`.
    /// Senkron okuma (Splash ilk kare: force-update kapısı) ve offline fallback için.
    func cachedConfig() -> RemoteConfig?

    /// Cache 24h TTL içinde mi? Cache yoksa `false`. Soğuk açılışta "taze ise ağ
    /// çağrısı yapma" kararı için.
    func isCacheFresh() -> Bool

    /// Ağdan tazeler: decode → cache (yük + zaman damgası) yaz → flag snapshot'ı bir
    /// sonraki launch için yaz. Ağ yoksa / bozuk yük → GRACEFUL: son cache'i (bayat
    /// olabilir) döner, yoksa `nil` — throw ETMEZ, uygulamayı DURDURMAZ (03 §11 offline).
    @discardableResult
    func refresh() async -> RemoteConfig?
}

public extension RemoteConfigProviding {
    /// Soğuk açılış yolu (05 §13.1): cache TAZE ise ağ çağrısı YAPMADAN onu döner;
    /// bayat/yoksa `refresh()`. Offline'da `refresh()` graceful davrandığı için bu da
    /// güvenlidir (bayat cache veya `nil`). Arka plan tazeleme çağıranın (app_open)
    /// ayrıca `refresh()` çağırmasıyla yapılır — atama oturum ortasında değişmez (08 §7.1).
    func loadForColdStart() async -> RemoteConfig? {
        if isCacheFresh(), let cached = cachedConfig() {
            return cached
        }
        return await refresh()
    }
}
