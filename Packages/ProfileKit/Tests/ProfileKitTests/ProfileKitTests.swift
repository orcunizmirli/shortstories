import Testing
import AppFoundation
@testable import ProfileKit

@Test func modulDerleniyorVeIDTipleriContentKitsizGorunur() {
    #expect(ProfileKitModule.name == "ProfileKit")
    #expect(SeriesID(rawValue: "s1").rawValue == "s1") // R3: ID tipleri AF'den, ContentKit import'suz
}
