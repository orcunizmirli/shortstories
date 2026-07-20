import AppFoundation
import Foundation
import RewardsKit
import WalletKit
import XCTest
@testable import ShortSeriesApp

/// SS-114 App wiring: RewardsKit `RewardedAdService` → WalletKit `RewardedAdUnlocking` port köprüsü +
/// canlı `AdUnlockGateway` (POST /rewards/ad-unlock) eşlemeleri. SAF `map` dönüşümleri + VIP reklamsızlık
/// üst kapısı + 429/422 iş hatası eşlemesi. (App target CI dışıdır; Xcode/simülatör doğrulaması içindir.)
@MainActor
final class RewardedAdWiringTests: XCTestCase {
    // MARK: - SAF availability eşlemesi (RewardsKit → WalletKit + dailyCap enjeksiyonu)

    func testMapAvailabilityAvailableCarriesRemainingAndCap() {
        let mapped = RewardedAdUnlockingAdapter.map(.available(remaining: 3), dailyCap: 5)
        XCTAssertEqual(mapped, .available(remaining: 3, dailyCap: 5))
        XCTAssertTrue(mapped.isActionable)
        XCTAssertEqual(mapped.remainingIndicator?.remaining, 3)
        XCTAssertEqual(mapped.remainingIndicator?.dailyCap, 5)
    }

    func testMapAvailabilityCapReachedIsVisibleButNotActionable() {
        let resets = Date(timeIntervalSince1970: 2_000_000)
        let mapped = RewardedAdUnlockingAdapter.map(.capReached(resetsAt: resets), dailyCap: 5)
        XCTAssertEqual(mapped, .capReached(resetsAt: resets, dailyCap: 5))
        XCTAssertTrue(mapped.isVisible)
        XCTAssertFalse(mapped.isActionable)
    }

    func testMapAvailabilityHidden() {
        XCTAssertEqual(RewardedAdUnlockingAdapter.map(.hidden, dailyCap: 5), .hidden)
        XCTAssertFalse(RewardedAdUnlockingAdapter.map(.hidden, dailyCap: 5).isVisible)
    }

    // MARK: - SAF result eşlemesi

    func testMapResultUnlockedCarriesRemainingToday() {
        let outcome = AdUnlockOutcome(target: .episode(id: "ep_9"), remainingToday: 2, coinBalance: nil)
        XCTAssertEqual(RewardedAdUnlockingAdapter.map(.unlocked(outcome)), .unlocked(remainingToday: 2))
    }

    func testMapResultTerminalStates() {
        let resets = Date(timeIntervalSince1970: 3_000_000)
        XCTAssertEqual(RewardedAdUnlockingAdapter.map(.dismissedEarly), .dismissedEarly)
        XCTAssertEqual(RewardedAdUnlockingAdapter.map(.noFill), .noFill)
        XCTAssertEqual(RewardedAdUnlockingAdapter.map(.failed), .failed)
        XCTAssertEqual(RewardedAdUnlockingAdapter.map(.capReached(resetsAt: resets)), .capReached(resetsAt: resets))
        XCTAssertEqual(RewardedAdUnlockingAdapter.map(.rewardRejected), .rewardRejected)
    }

    // MARK: - VIP reklamsızlık üst kapısı (06 §9.5 — zorunlu-reklam YOK)

    func testVIPPreloadIsNoOpAndAvailabilityHidden() async {
        let provider = StubRewardedAdProvider(fill: true, outcome: .completed(sampleProof))
        let adapter = makeAdapter(provider: provider, gateway: StubAdUnlockGateway(.success(sampleOutcome)), isVIP: true)

        await adapter.preload()
        let availability = await adapter.availability()

        XCTAssertEqual(provider.preloadCount, 0) // VIP'e reklam SDK'sı ön-yüklenmez
        XCTAssertEqual(availability, .hidden) // VIP'e satır gizli
    }

    // MARK: - Bayrak/fill kapısı

    func testAvailabilityHiddenWhenFlagOff() async {
        let provider = StubRewardedAdProvider(fill: true, outcome: .completed(sampleProof))
        let adapter = makeAdapter(provider: provider, isVIP: false, flag: false)

        let availability = await adapter.availability()

        XCTAssertEqual(availability, .hidden)
    }

    func testAvailabilityAvailableWhenFlagOnAndFilled() async {
        let provider = StubRewardedAdProvider(fill: true, outcome: .completed(sampleProof))
        let adapter = makeAdapter(provider: provider, isVIP: false, flag: true, cap: 5)

        let availability = await adapter.availability()

        // remaining server'dan gelmiyor (ilk gösterim) → nil; cap config'ten enjekte.
        XCTAssertEqual(availability, .available(remaining: nil, dailyCap: 5))
        XCTAssertTrue(availability.isActionable)
    }

    func testAvailabilityHiddenWhenNoFill() async {
        let provider = StubRewardedAdProvider(fill: false, outcome: .completed(sampleProof))
        let adapter = makeAdapter(provider: provider, isVIP: false, flag: true)

        let availability = await adapter.availability()

        XCTAssertEqual(availability, .hidden)
    }

    // MARK: - İzle→unlock (server-otoriter)

    func testWatchAdUnlocksAndPassesRemainingToday() async {
        let provider = StubRewardedAdProvider(fill: true, outcome: .completed(sampleProof))
        let outcome = AdUnlockOutcome(target: .episode(id: "ep_12"), remainingToday: 4, coinBalance: nil)
        let adapter = makeAdapter(provider: provider, gateway: StubAdUnlockGateway(.success(outcome)), isVIP: false)

        let result = await adapter.watchAdToUnlock(episodeID: EpisodeID("ep_12"))

        XCTAssertEqual(result, .unlocked(remainingToday: 4))
        XCTAssertEqual(provider.showCount, 1)
    }

    // MARK: - Canlı AdUnlockGateway (POST /rewards/ad-unlock) eşlemeleri

    func testGatewayDecodesOutcomeSnapshot() async throws {
        let client = StubAPIClient()
        let json = #"{"remainingToday":3,"wallet":{"purchasedCoins":100,"earnedCoins":30}}"#
        client.stub("/rewards/ad-unlock", data: Data(json.utf8))
        let gateway = APIAdUnlockGateway(client: client, makeIdempotencyKey: { "idem_1" })

        let outcome = try await gateway.requestAdUnlock(AdUnlockRequest(target: .episode(id: "ep_7"), proof: sampleProof))

        XCTAssertEqual(outcome.target, .episode(id: "ep_7")) // istek target'ı ile eşleşir
        XCTAssertEqual(outcome.remainingToday, 3)
        XCTAssertEqual(outcome.coinBalance, 130) // wallet kesesinden türetilir (purchased + earned)
        XCTAssertEqual(client.receivedPaths, ["/rewards/ad-unlock"])
    }

    func testGateway429MapsToCapReached() async {
        let client = StubAPIClient()
        client.stub("/rewards/ad-unlock", error: .network(.server(status: 429)))
        let gateway = APIAdUnlockGateway(client: client, makeIdempotencyKey: { "idem_1" })

        await assertThrows(gateway, expected: .capReached(resetsAt: nil))
    }

    func testGateway422MapsToRewardRejected() async {
        let client = StubAPIClient()
        client.stub("/rewards/ad-unlock", error: .network(.server(status: 422)))
        let gateway = APIAdUnlockGateway(client: client, makeIdempotencyKey: { "idem_1" })

        await assertThrows(gateway, expected: .rewardRejected)
    }

    func testGatewayTransportErrorRethrows() async {
        // Diğer taşıma hataları (offline/timeout) tipli AppError olarak YÜZER → RewardedAdService `.failed`.
        let client = StubAPIClient()
        client.stub("/rewards/ad-unlock", error: .network(.timeout))
        let gateway = APIAdUnlockGateway(client: client, makeIdempotencyKey: { "idem_1" })

        do {
            _ = try await gateway.requestAdUnlock(AdUnlockRequest(target: .episode(id: "ep_7"), proof: sampleProof))
            XCTFail("Taşıma hatası yüzmeliydi")
        } catch let error as AppError {
            XCTAssertEqual(error, .network(.timeout))
        } catch {
            XCTFail("Beklenmeyen hata tipi: \(error)")
        }
    }

    // MARK: - Wire gövdesi (05 §4.7 İÇ-İÇE `proof` zarfı — SSV kanıtı)

    /// `.episode` hedefinde gövde §4.7 iç-içe şekildedir: `proof` alt-nesnesi provider/nonce/proofPayload
    /// taşır, `episodeId` üst düzeyde present. Düzleştirilmiş provider/nonce ve spec-dışı `rewardType`
    /// üst düzeyde BULUNMAZ (aksi halde backend `proof`'u bulamaz → SSV başarısız, kilit açılmaz).
    func testWireBodyNestsProofEnvelopeForEpisode() async throws {
        let client = StubAPIClient()
        client.stub("/rewards/ad-unlock", data: Data(#"{"remainingToday":3}"#.utf8))
        let gateway = APIAdUnlockGateway(client: client, makeIdempotencyKey: { "idem_1" })

        _ = try await gateway.requestAdUnlock(AdUnlockRequest(
            target: .episode(id: "ep_5410bf"),
            proof: RewardProof(provider: "admob", nonce: "adn_84f2", proofPayload: ["signature": "sig"])
        ))

        let data = try XCTUnwrap(client.capturedBody(for: "/rewards/ad-unlock"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // İç-içe `proof` zarfı (§4.7 normatif).
        let proof = try XCTUnwrap(json["proof"] as? [String: Any], "gövde `proof` alt-nesnesi taşımalı")
        XCTAssertEqual(proof["provider"] as? String, "admob")
        XCTAssertEqual(proof["nonce"] as? String, "adn_84f2")
        let proofPayload = try XCTUnwrap(proof["proofPayload"] as? [String: Any])
        XCTAssertEqual(proofPayload["signature"] as? String, "sig")

        // Üst düzey episodeId present (§4.7 örneği).
        XCTAssertEqual(json["episodeId"] as? String, "ep_5410bf")

        // Düzleştirme/spec-dışı alanlar üst düzeyde YOK.
        XCTAssertNil(json["provider"], "provider üst düzeye düzleştirilMEMELİ")
        XCTAssertNil(json["nonce"], "nonce üst düzeye düzleştirilMEMELİ")
        XCTAssertNil(json["proofPayload"], "proofPayload üst düzeye düzleştirilMEMELİ")
        XCTAssertNil(json["rewardType"], "`rewardType` spec'te yok — gönderilMEMELİ")
    }

    /// `.coinReward` hedefinde `episodeId` omit edilir (§4.7 coinReward'ı belgelemez) ama `proof` yine gönderilir.
    func testWireBodyOmitsEpisodeIdForCoinReward() async throws {
        let client = StubAPIClient()
        client.stub("/rewards/ad-unlock", data: Data(#"{"remainingToday":3}"#.utf8))
        let gateway = APIAdUnlockGateway(client: client, makeIdempotencyKey: { "idem_1" })

        _ = try await gateway.requestAdUnlock(AdUnlockRequest(target: .coinReward, proof: sampleProof))

        let data = try XCTUnwrap(client.capturedBody(for: "/rewards/ad-unlock"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["episodeId"], "coinReward yolunda episodeId omit edilmeli")
        let proof = try XCTUnwrap(json["proof"] as? [String: Any], "proof yine de gönderilmeli")
        XCTAssertEqual(proof["provider"] as? String, "admob")
    }

    // MARK: - Yardımcılar

    private var sampleProof: RewardProof {
        RewardProof(provider: "admob", nonce: "adn_1", proofPayload: ["signature": "sig"])
    }

    private var sampleOutcome: AdUnlockOutcome {
        AdUnlockOutcome(target: .episode(id: "ep_1"), remainingToday: 4, coinBalance: nil)
    }

    private func makeAdapter(
        provider: StubRewardedAdProvider,
        gateway: StubAdUnlockGateway? = nil,
        isVIP: Bool,
        flag: Bool = true,
        cap: Int? = 5
    ) -> RewardedAdUnlockingAdapter {
        let service = RewardedAdService(
            provider: provider,
            gateway: gateway ?? StubAdUnlockGateway(.success(sampleOutcome)),
            analytics: NoopAnalytics(),
            variant: .adSecondary
        )
        return RewardedAdUnlockingAdapter(
            service: service,
            isVIP: { isVIP },
            rewardedAdsEnabled: { flag },
            dailyCap: { cap }
        )
    }

    private func assertThrows(
        _ gateway: APIAdUnlockGateway,
        expected: AdUnlockError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await gateway.requestAdUnlock(AdUnlockRequest(target: .episode(id: "ep_7"), proof: sampleProof))
            XCTFail("AdUnlockError beklendi", file: file, line: line)
        } catch let error as AdUnlockError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Beklenmeyen hata tipi: \(error)", file: file, line: line)
        }
    }
}

// MARK: - Test doubles (AppTests AppFoundationTestSupport'u linklemez → yerel dar çiftler)

private final class StubRewardedAdProvider: RewardedAdProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let fill: Bool
    private let outcome: AdWatchOutcome
    private(set) var preloadCount = 0
    private(set) var showCount = 0

    init(fill: Bool, outcome: AdWatchOutcome) {
        self.fill = fill
        self.outcome = outcome
    }

    func preload() async {
        lock.withLock { preloadCount += 1 }
    }

    func isAdAvailable() async -> Bool {
        fill
    }

    func showAd() async -> AdWatchOutcome {
        lock.withLock { showCount += 1 }
        return outcome
    }
}

private final class StubAdUnlockGateway: AdUnlockGateway, @unchecked Sendable {
    private let result: Result<AdUnlockOutcome, Error>

    init(_ result: Result<AdUnlockOutcome, Error>) {
        self.result = result
    }

    func requestAdUnlock(_: AdUnlockRequest) async throws -> AdUnlockOutcome {
        try result.get()
    }
}

private final class NoopAnalytics: AnalyticsTracking, @unchecked Sendable {
    func track(_: String, parameters _: [String: AnalyticsValue]) {}
}

/// Yerel stub `APIClientProtocol` — yol ile anahtarlı; canlı `APIClient` ile aynı sınır dönüşümü.
private final class StubAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<Data, AppError>] = [:]
    private var paths: [String] = []
    private var bodies: [String: Data] = [:]
    private let decoder = JSONDecoder.shortSeriesDefault()

    var receivedPaths: [String] {
        lock.withLock { paths }
    }

    /// Gönderilen isteğin gövdesini (varsa) JSON'a encode edip yakalar — wire-body yapı doğrulaması için.
    func capturedBody(for path: String) -> Data? {
        lock.withLock { bodies[path] }
    }

    func stub(_ path: String, data: Data) {
        lock.withLock { responses[path] = .success(data) }
    }

    func stub(_ path: String, error: AppError) {
        lock.withLock { responses[path] = .failure(error) }
    }

    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let result: Result<Data, AppError>? = lock.withLock {
            paths.append(endpoint.path)
            if let body = endpoint.body {
                bodies[endpoint.path] = try? JSONEncoder().encode(body)
            }
            return responses[endpoint.path]
        }
        guard let result else {
            throw AppError.unexpected(underlying: "StubAPIClient: '\(endpoint.path)' için stub yok")
        }
        switch result {
        case let .success(data):
            do {
                return try decoder.decode(E.Response.self, from: data)
            } catch {
                throw AppError.network(.decoding)
            }
        case let .failure(error):
            throw error
        }
    }
}
