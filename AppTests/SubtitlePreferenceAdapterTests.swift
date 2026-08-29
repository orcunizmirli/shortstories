import ProfileKit
import XCTest
@testable import ShortSeriesApp

/// SS-046 köprüsü: App `SubtitlePreferenceAdapter`, ProfileKit `SubtitleLanguageProviding`'i PlayerKit'in
/// ilkel-tipli `SubtitlePreferenceProviding`'ine indirger — `SubtitleLanguage.code` (nil = kapalı) taşır.
final class SubtitlePreferenceAdapterTests: XCTestCase {
    private final class FakeProvider: SubtitleLanguageProviding, @unchecked Sendable {
        let current: SubtitleLanguage
        private let updates: [SubtitleLanguage]
        init(current: SubtitleLanguage, updates: [SubtitleLanguage] = []) {
            self.current = current
            self.updates = updates
        }

        var currentSubtitleLanguage: SubtitleLanguage {
            current
        }

        func subtitleLanguageUpdates() -> AsyncStream<SubtitleLanguage> {
            AsyncStream { continuation in
                for language in updates {
                    continuation.yield(language)
                }
                continuation.finish()
            }
        }
    }

    func testCurrentCodeMapsLanguageCode() {
        XCTAssertNil(SubtitlePreferenceAdapter(source: FakeProvider(current: .off)).currentSubtitleCode)
        XCTAssertEqual(SubtitlePreferenceAdapter(source: FakeProvider(current: .turkish)).currentSubtitleCode, "tr")
        XCTAssertEqual(SubtitlePreferenceAdapter(source: FakeProvider(current: .english)).currentSubtitleCode, "en")
    }

    func testStreamMapsLanguagesToCodes() async {
        let adapter = SubtitlePreferenceAdapter(
            source: FakeProvider(current: .off, updates: [.english, .off, .turkish])
        )
        var codes: [String?] = []
        for await code in adapter.subtitleCodeUpdates() {
            codes.append(code)
        }
        XCTAssertEqual(codes, ["en", nil, "tr"]) // .off → nil taşınır
    }
}
