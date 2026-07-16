import AppFoundation
import XCTest
@testable import ShortSeriesApp

/// SS-141 — Rich push SAF çekirdeğinin izole testleri. NSE runtime'ı (gerçek APNs/`UNNotification`) yerine
/// karar mantığı (görsel URL çıkarma + geçerlilik, kategori belirleme, attachment uzantı/MIME kararı)
/// doğrudan test edilir. Ham `UNNotification*` tipi kullanılmaz (tasarım sözleşmesi). Bu hedef CI'da KOŞMAZ
/// (App target CI dışı); Xcode/lokal doğrulama içindir.
final class RichPushPlanTests: XCTestCase {
    // MARK: - Görsel URL çıkarma + geçerlilik

    func testImageURLExtractedFromCamelCaseKey() {
        let url = RichPushPresentation.imageURL(from: ["imageURL": "https://cdn.example.com/cover_srs_123.jpg"])
        XCTAssertEqual(url, URL(string: "https://cdn.example.com/cover_srs_123.jpg"))
    }

    func testImageURLExtractedFromSnakeCaseKey() {
        let url = RichPushPresentation.imageURL(from: ["image_url": "https://cdn.example.com/a.png"])
        XCTAssertEqual(url, URL(string: "https://cdn.example.com/a.png"))
    }

    func testImageURLCamelCaseTakesPriorityOverAliases() {
        let url = RichPushPresentation.imageURL(from: [
            "imageURL": "https://cdn.example.com/primary.jpg",
            "image_url": "https://cdn.example.com/secondary.jpg"
        ])
        XCTAssertEqual(url, URL(string: "https://cdn.example.com/primary.jpg"))
    }

    func testHTTPImageURLAccepted() {
        XCTAssertNotNil(RichPushPresentation.validatedImageURL("http://cdn.example.com/a.jpg"))
    }

    func testFileSchemeImageURLRejected() {
        XCTAssertNil(RichPushPresentation.validatedImageURL("file:///tmp/evil.jpg"))
    }

    func testDataSchemeImageURLRejected() {
        XCTAssertNil(RichPushPresentation.validatedImageURL("data:image/png;base64,AAAA"))
    }

    func testSchemelessOrEmptyImageURLRejected() {
        XCTAssertNil(RichPushPresentation.validatedImageURL("cdn.example.com/a.jpg")) // host yok, şema yok
        XCTAssertNil(RichPushPresentation.validatedImageURL(""))
    }

    func testMissingImageKeyYieldsNil() {
        XCTAssertNil(RichPushPresentation.imageURL(from: ["route": "shortseries://series/s1/episode/2"]))
    }

    func testNonStringImageValueIgnored() {
        XCTAssertNil(RichPushPresentation.imageURL(from: ["imageURL": 42]))
    }

    // MARK: - Kategori belirleme (mevcut PushPayload tip-çözümünü yeniden kullanır)

    func testNewEpisodeCategoryFromExplicitType() {
        let id = RichPushPresentation.categoryIdentifier(from: [
            "type": "new_episode",
            "route": "shortseries://series/srs_1/episode/2"
        ])
        XCTAssertEqual(id, RichPushCategory.newEpisodeIdentifier)
    }

    func testContinueCategoryFromExplicitType() {
        let id = RichPushPresentation.categoryIdentifier(from: [
            "type": "continue",
            "route": "shortseries://play/srs_1?t=42"
        ])
        XCTAssertEqual(id, RichPushCategory.continueIdentifier)
    }

    func testCategoryDerivedFromRouteWhenTypeAbsent() {
        // type taşımayan payload → PushPayload rota şeklinden türetir (series → yeni bölüm).
        let id = RichPushPresentation.categoryIdentifier(from: ["route": "shortseries://series/srs_1/episode/2"])
        XCTAssertEqual(id, RichPushCategory.newEpisodeIdentifier)
    }

    func testUnknownCampaignTypeYieldsNilCategory() {
        // F1 dışı tip → PushPayload nil → kategori yok (yine de metin+görsel teslim edilebilir).
        let id = RichPushPresentation.categoryIdentifier(from: [
            "type": "coin_reward",
            "route": "shortseries://store/coins"
        ])
        XCTAssertNil(id)
    }

    func testMissingRouteYieldsNilCategory() {
        XCTAssertNil(RichPushPresentation.categoryIdentifier(from: ["type": "new_episode"]))
    }

    func testCategoryIdentifierMapping() {
        XCTAssertEqual(RichPushCategory.identifier(for: .newEpisode), RichPushCategory.newEpisodeIdentifier)
        XCTAssertEqual(RichPushCategory.identifier(for: .continueWatching), RichPushCategory.continueIdentifier)
    }

    // MARK: - Birleşik sunum kararı

    func testPresentationCombinesImageAndCategory() {
        let presentation = RichPushPresentation(userInfo: [
            "type": "new_episode",
            "route": "shortseries://series/srs_1/episode/2",
            "imageURL": "https://cdn.example.com/cover.jpg"
        ])
        XCTAssertEqual(presentation.imageURL, URL(string: "https://cdn.example.com/cover.jpg"))
        XCTAssertEqual(presentation.categoryIdentifier, RichPushCategory.newEpisodeIdentifier)
    }

    func testPresentationDegradesToTextOnlyWhenNothingRich() {
        // Görsel yok + tip çözülemez → her iki alan nil (NSE metin-only teslim eder, push düşmez).
        let presentation = RichPushPresentation(userInfo: ["foo": "bar"])
        XCTAssertNil(presentation.imageURL)
        XCTAssertNil(presentation.categoryIdentifier)
    }

    // MARK: - Attachment dosya-uzantısı / MIME kararı

    func testFileExtensionFromKnownURLExtension() throws {
        let png = try XCTUnwrap(URL(string: "https://cdn.example.com/a.png"))
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: png, mimeType: nil), "png")
    }

    func testJPEGURLExtensionNormalizedToJPG() throws {
        let jpeg = try XCTUnwrap(URL(string: "https://cdn.example.com/a.jpeg"))
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: jpeg, mimeType: nil), "jpg")
    }

    func testUppercaseURLExtensionNormalized() throws {
        let heic = try XCTUnwrap(URL(string: "https://cdn.example.com/A.HEIC"))
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: heic, mimeType: nil), "heic")
    }

    func testFileExtensionFallsBackToMIMEWhenURLHasNone() throws {
        let noExt = try XCTUnwrap(URL(string: "https://cdn.example.com/image"))
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: noExt, mimeType: "image/png"), "png")
    }

    func testFileExtensionIgnoresMIMEParameters() throws {
        let noExt = try XCTUnwrap(URL(string: "https://cdn.example.com/image"))
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: noExt, mimeType: "image/jpeg; charset=binary"), "jpg")
    }

    func testFileExtensionDefaultsToJPGWhenUnknown() throws {
        let noExt = try XCTUnwrap(URL(string: "https://cdn.example.com/image"))
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: noExt, mimeType: "application/octet-stream"), "jpg")
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: noExt, mimeType: nil), "jpg")
    }

    func testWebPSupported() throws {
        let webp = try XCTUnwrap(URL(string: "https://cdn.example.com/a.webp"))
        XCTAssertEqual(RichPushAttachment.fileExtension(forURL: webp, mimeType: nil), "webp")
    }

    // MARK: - Yanıt görsel kabulü

    func testImageMIMEAccepted() {
        XCTAssertTrue(RichPushAttachment.isAcceptableImageResponse(mimeType: "image/jpeg"))
    }

    func testNonImageMIMERejected() {
        XCTAssertFalse(RichPushAttachment.isAcceptableImageResponse(mimeType: "text/html"))
    }

    func testUnknownMIMEAcceptedTrustingExtension() {
        XCTAssertTrue(RichPushAttachment.isAcceptableImageResponse(mimeType: nil))
        XCTAssertTrue(RichPushAttachment.isAcceptableImageResponse(mimeType: ""))
    }

    // MARK: - Kategori kayıt tanımları (AppDelegate ile aynı kaynak)

    func testRegisteredCategoriesCoverBothCampaignTypes() {
        let identifiers = Set(RichPushCategory.all.map(\.identifier))
        XCTAssertEqual(identifiers, [RichPushCategory.newEpisodeIdentifier, RichPushCategory.continueIdentifier])
    }

    func testNewEpisodeCategoryHasWatchAction() {
        let category = RichPushCategory.all.first { $0.identifier == RichPushCategory.newEpisodeIdentifier }
        XCTAssertEqual(category?.actions.map(\.title), ["İzle"])
        XCTAssertEqual(category?.actions.first?.opensApp, true)
    }

    func testContinueCategoryHasResumeAction() {
        let category = RichPushCategory.all.first { $0.identifier == RichPushCategory.continueIdentifier }
        XCTAssertEqual(category?.actions.map(\.title), ["Devam Et"])
        XCTAssertEqual(category?.actions.first?.opensApp, true)
    }
}
