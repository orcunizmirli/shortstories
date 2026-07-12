import AppFoundation
import Testing
@testable import RewardsKit

@Test func modulDerleniyorVeIDTipleriContentKitsizGorunur() {
    #expect(RewardsKitModule.name == "RewardsKit")
    #expect(SeriesID(rawValue: "s1").rawValue == "s1") // R3: ID tipleri AF'den, ContentKit import'suz
}
