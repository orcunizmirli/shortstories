import AppFoundation
import Foundation
import Network
import PlayerKit

// PlayerKit çalışma-zamanı portlarının canlı adaptörleri (04 §5.3/5.4, R8). PlayerKit ProfileKit/
// AppFoundation'ı import etmeden bu portlara bağlanır; App kompozisyonu somut kaynakları verir.

/// PlayerKit `NetworkConditionProviding` → `NWPathMonitor` (SS-026). Aktif arayüz sınıfı + kısıtlı
/// (Low Data Mode) sinyali, veri-tasarrufu/bitrate tavanı kararlarını besler. Monitor arka plan
/// kuyruğunda sürekli günceller; son koşul kilitli okunur (senkron, ağ çağrısı yok).
///
/// `@unchecked Sendable`: paylaşılan `latest` `NSLock` ile korunur; `NWPathMonitor` kendi kuyruğunda
/// callback verir.
final class NWNetworkConditionProvider: NetworkConditionProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shortseries.network-monitor")
    private let lock = NSLock()
    private var latest = NetworkCondition(interface: .unknown)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let condition = Self.condition(from: path)
            lock.withLock { latest = condition }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    func currentCondition() async -> NetworkCondition {
        lock.withLock { latest }
    }

    /// Saf dönüşüm (izole test edilir kalıp): `NWPath` → taşıma-bağımsız `NetworkCondition`.
    static func condition(from path: NWPath) -> NetworkCondition {
        let interface: NetworkCondition.Interface = if path.usesInterfaceType(.wifi) {
            .wifi
        } else if path.usesInterfaceType(.cellular) {
            .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            .wired
        } else {
            .unknown
        }
        return NetworkCondition(interface: interface, isConstrained: path.isConstrained)
    }
}

/// PlayerKit `PlaybackPreferencesProviding` → `PreferencesStoring` (SS-048, 04 §5.3). Veri tasarrufu
/// tercihi tek kaynak UserDefaults'tan okunur (Ayarlar yazar). ProfileKit'in aynı adlı portundan
/// AYRIDIR (bu yüzey yalnız `isDataSaverEnabled` sorar; player prefetch/bitrate kararını buradan türetir).
struct PreferencesDataSaverProvider: PlayerKit.PlaybackPreferencesProviding {
    private let preferences: any PreferencesStoring

    init(preferences: any PreferencesStoring) {
        self.preferences = preferences
    }

    func isDataSaverEnabled() async -> Bool {
        preferences.value(for: PreferenceKeys.dataSaverEnabled)
    }
}
