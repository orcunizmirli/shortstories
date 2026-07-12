import Testing
import AppFoundation
@testable import AnalyticsKit

@Test func modulDerleniyorVeAppFoundationGorunur() {
    #expect(AnalyticsKitModule.name == "AnalyticsKit")
    #expect(SeriesID(rawValue: "s1").rawValue == "s1") // AF SharedTypes kanıtı
}
