import Foundation

/// Ağ koşulunun taşıma-bağımsız anlık görüntüsü (04 §5.3 tablosunun girdisi).
public struct NetworkCondition: Sendable, Equatable {
    /// Aktif arayüz sınıfı.
    public enum Interface: Sendable, Equatable {
        case wifi
        case cellular
        case wired
        case unknown
    }

    public let interface: Interface
    /// iOS Low Data Mode (`allowsExpensiveNetworkAccess` sinyali): veri tasarrufu
    /// davranışına otomatik düşülür (04 §5.3).
    public let isConstrained: Bool

    public init(interface: Interface, isConstrained: Bool = false) {
        self.interface = interface
        self.isConstrained = isConstrained
    }

    public static let wifi = NetworkCondition(interface: .wifi)
    public static let cellular = NetworkCondition(interface: .cellular)
}

/// Ağ koşulu portu: canlı uygulama NWPathMonitor sarmalayıcısıdır (SS-026,
/// AppFoundation dilimi); PlayerKit yalnız bu portu görür — ağ tasarrufu sinyali
/// için protokol sınırı (04 §5.4 `NetworkConditionMonitor` karşılığı).
public protocol NetworkConditionProviding: Sendable {
    func currentCondition() async -> NetworkCondition
}

/// Oynatma tercihleri portu: veri tasarrufu modu Ayarlar → oynatma tercihlerinde
/// yaşar (04 §5.3); canlı uygulama ProfileKit/Ayarlar tarafından beslenir,
/// kompozisyon ShortSeriesApp'tedir.
public protocol PlaybackPreferencesProviding: Sendable {
    func isDataSaverEnabled() async -> Bool
}
