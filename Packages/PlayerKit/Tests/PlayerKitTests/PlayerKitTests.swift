import Testing
import AppFoundation
import ContentKit
@testable import PlayerKit

@Test func modulDerleniyorVeBagimliliklarGorunur() {
    #expect(PlayerKitModule.name == "PlayerKit")
    #expect(SeriesID(rawValue: "s1").rawValue == "s1") // AF SharedTypes kanıtı
    #expect(ContentKitModule.name == "ContentKit") // R3: içerik gösteren feature ContentKit'e bağlanabilir
}
