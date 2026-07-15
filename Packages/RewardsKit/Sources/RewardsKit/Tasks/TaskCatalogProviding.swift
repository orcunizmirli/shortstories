/// Görev kataloğu OKUMA portu (SS-112, R8). RewardsKit tanımlar (tüketici), App canlı `APIClient` /
/// remote config'e bağlar (üretici): `GET /missions`. Katalog TAMAMEN sunucudan gelir — istemci sabit
/// görev listesi VARSAYMAZ (07 §4.1). Kalıp: LibraryKit `LibraryCatalogReading`,
/// ProfileKit `WalletSummaryReading`.
///
/// App adaptörü JSON'ı `RewardTask`'a map eder; bilinmeyen `kind`/`state` değerlerini ileri-uyumlu
/// `.unknown`'a düşürür (`UnknownDecodable` kalıbı, 07 §4.3). RewardsKit ağ/JSON GÖRMEZ.
public protocol TaskCatalogProviding: Sendable {
    /// `GET /missions` → güncel görev kataloğu. Transport hatası `AppError` fırlatır.
    func tasks() async throws -> [RewardTask]
}
