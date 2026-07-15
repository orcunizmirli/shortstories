/// Gerçek istemci-tarafı görev ilerlemesi OKUMA portu (SS-112, R8). RewardsKit tanımlar (tüketici),
/// App gerçek event kaynaklarına bağlar (üretici): izleme süresi (player heartbeat), favorileme
/// (LibraryKit aksiyonu), paylaşım (paylaşım sheet completion), bildirim izni (APNs authorization).
///
/// RewardsKit event ÜRETMEZ, yalnız OKUR. Sağlanan değerler görev tipine göre canlı ilerleme anlık
/// görüntüsüdür ve YALNIZ GÖRÜNTÜLEMEDİR: ilerleme çubuğunu oturum içinde tepkili ilerletir, ama
/// claim-edilebilirliği ETKİLEMEZ (doğruluk kaynağı sunucu `state`'idir — 06 §, R6; fraud kontrolü
/// backend'te türetilir, 07 §4.3). Kalıp: `RewardsWalletReading` current-value + akış sözleşmesi.
public protocol TaskProgressReading: Sendable {
    /// Görev tipine göre anlık istemci-tarafı ilerleme (ilk yüklemede overlay için).
    func currentProgress() async -> [RewardTask.Kind: Int]

    /// Canlı ilerleme akışı; OdulMerkezi açıkken çubuk güncellemesi. Abone olunca mevcut değeri
    /// replay eder (geç abone güncel ilerlemeyi kaçırmaz).
    func progressUpdates() -> AsyncStream<[RewardTask.Kind: Int]>
}
