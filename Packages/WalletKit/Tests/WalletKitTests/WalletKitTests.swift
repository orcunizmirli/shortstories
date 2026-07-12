import AppFoundation
import Testing
@testable import WalletKit

@Test func modulDerleniyorVeIDTipleriContentKitsizGorunur() {
    #expect(WalletKitModule.name == "WalletKit")
    #expect(EpisodeID(rawValue: "e1").rawValue == "e1") // R3: ID tipleri AF'den, ContentKit import'suz
}
