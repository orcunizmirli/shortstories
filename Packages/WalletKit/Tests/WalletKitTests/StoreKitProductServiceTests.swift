import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// Ürün yükleme (SS-090): App Store istenen ürünlerden bazılarını (ASC'de pasif/reddedilmiş)
/// eksik döndürebilir. Her eksik ID için `iap_product_missing` analitik event'i emit edilir
/// (06 §4.2) — UI o ID'yi gizler. StoreKit'siz izole edilebilir seam testi.
struct StoreKitProductServiceTests {
    @Test func eksikUrunIDsiIapProductMissingEmitEder() async {
        let analytics = MockAnalytics()
        let service = StoreKitProductService(analytics: analytics)

        // İstenen üç ID'den yalnız "b" App Store'dan gelmedi → yalnız o emit edilir.
        await service.reportMissingProducts(requested: ["a", "b", "c"], loadedIDs: ["a", "c"])

        #expect(analytics.events == [
            MockAnalytics.Event(name: "iap_product_missing", parameters: ["product_id": .string("b")])
        ])
    }

    @Test func birdenFazlaEksikIDHerBiriIcinEmitEder() async {
        let analytics = MockAnalytics()
        let service = StoreKitProductService(analytics: analytics)

        await service.reportMissingProducts(requested: ["a", "b", "c"], loadedIDs: ["a"])

        #expect(analytics.eventNames == ["iap_product_missing", "iap_product_missing"])
    }

    @Test func tumUrunlerGelmisseHicEmitYok() async {
        let analytics = MockAnalytics()
        let service = StoreKitProductService(analytics: analytics)

        await service.reportMissingProducts(requested: ["a", "b"], loadedIDs: ["a", "b"])

        #expect(analytics.events.isEmpty)
    }
}
