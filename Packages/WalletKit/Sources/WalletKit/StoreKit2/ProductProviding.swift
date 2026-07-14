/// StoreKit ürün yükleme portu (SS-090). Canlı implementasyon `StoreKitProductService`
/// (`Product.products(for:)`); testler fake port ile kontrollü ürün seti döndürür.
public protocol ProductProviding: Sendable {
    /// App Store'dan ürünleri yükler. Eksik ID döndürebilir (ASC'de pasif/reddedilmiş ürün);
    /// çağıran eksik ID'yi UI'da gizler ve loglar (06 §4.2).
    func loadProducts(ids: [String]) async throws -> [StoreProduct]
}
