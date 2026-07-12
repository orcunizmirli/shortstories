import Testing
import AppFoundation
@testable import ContentKit

@Test func modulDerleniyorVeAppFoundationGorunur() {
    #expect(ContentKitModule.name == "ContentKit")
    #expect(SeriesID(rawValue: "s1").rawValue == "s1") // AF SharedTypes kanıtı
}
