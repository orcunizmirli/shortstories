import Testing
import AppFoundation
import ContentKit
@testable import DiscoverKit

@Test func modulDerleniyorVeBagimliliklarGorunur() {
    #expect(DiscoverKitModule.name == "DiscoverKit")
    #expect(SeriesID(rawValue: "s1").rawValue == "s1") // AF SharedTypes kanıtı
    #expect(ContentKitModule.name == "ContentKit") // R3: içerik gösteren feature ContentKit'e bağlanabilir
}
