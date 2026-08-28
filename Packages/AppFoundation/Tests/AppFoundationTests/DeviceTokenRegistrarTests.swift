import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

// MARK: - Saf kayıt kararı (deliverable 4: "token-kayıt kararı izole test")

struct DeviceRegistrationPlannerTests {
    private let tokenA = DeviceRegistrationSnapshot(apnsToken: "aaaa", notificationOptIn: true)

    @Test func firstTokenRegisters() {
        let plan = DeviceRegistrationPlanner.planForToken(token: "aaaa", optIn: true, lastSent: nil)
        #expect(plan == .register(tokenA))
    }

    @Test func sameTokenAndOptInSkips() {
        let plan = DeviceRegistrationPlanner.planForToken(token: "aaaa", optIn: true, lastSent: tokenA)
        #expect(plan == .skip)
    }

    @Test func changedTokenRegisters() {
        let plan = DeviceRegistrationPlanner.planForToken(token: "bbbb", optIn: true, lastSent: tokenA)
        #expect(plan == .register(DeviceRegistrationSnapshot(apnsToken: "bbbb", notificationOptIn: true)))
    }

    @Test func flippedOptInWithSameTokenRegisters() {
        let plan = DeviceRegistrationPlanner.planForToken(token: "aaaa", optIn: false, lastSent: tokenA)
        #expect(plan == .register(DeviceRegistrationSnapshot(apnsToken: "aaaa", notificationOptIn: false)))
    }

    @Test func optInChangeWithoutPriorTokenSkips() {
        #expect(DeviceRegistrationPlanner.planForOptInChange(optIn: false, lastSent: nil) == .skip)
    }

    @Test func optInChangeWithPriorTokenReusesToken() {
        let plan = DeviceRegistrationPlanner.planForOptInChange(optIn: false, lastSent: tokenA)
        #expect(plan == .register(DeviceRegistrationSnapshot(apnsToken: "aaaa", notificationOptIn: false)))
    }

    @Test func optInChangeToSameValueSkips() {
        #expect(DeviceRegistrationPlanner.planForOptInChange(optIn: true, lastSent: tokenA) == .skip)
    }
}

// MARK: - Canlı kayıt (mock APIClient + Keychain; gerçek APNs YOK)

struct DeviceTokenRegistrarTests {
    private let apiClient = MockAPIClient()
    private let secureStore = MockSecureStore()

    private func makeRegistrar(environment: APNsEnvironment = .sandbox) -> LiveDeviceTokenRegistrar {
        LiveDeviceTokenRegistrar(
            apiClient: apiClient,
            secureStore: secureStore,
            environment: environment,
            logger: MockLogger(),
            localeProvider: { "en-US" },
            timezoneProvider: { "America/New_York" }
        )
    }

    private func stubDevicesSuccess() {
        apiClient.stub("/devices", with: .success(Data())) // 204 No Content
    }

    private func lastBody() throws -> DeviceRegistrationEndpoint.Body {
        let endpoint = try #require(apiClient.receivedEndpoints.last as? DeviceRegistrationEndpoint)
        return endpoint.requestBody
    }

    // MARK: - İlk kayıt + gövde sözleşmesi (05 §4.9)

    @Test func firstTokenPostsDevicesWithContractBody() async throws {
        try secureStore.setString("device-42", forKey: .deviceID)
        stubDevicesSuccess()
        let registrar = makeRegistrar(environment: .production)

        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)

        #expect(apiClient.receivedPaths == ["/devices"])
        let body = try lastBody()
        #expect(body.deviceId == "device-42")
        #expect(body.apnsToken == "abc123")
        #expect(body.environment == "production")
        #expect(body.locale == "en-US")
        #expect(body.timezone == "America/New_York")
        #expect(body.notificationOptIn == true)
    }

    @Test func registrationPersistsSnapshotToKeychain() async throws {
        stubDevicesSuccess()
        let registrar = makeRegistrar()

        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)

        let stored = try #require(try secureStore.data(forKey: .pushRegistration))
        let snapshot = try JSONDecoder().decode(DeviceRegistrationSnapshot.self, from: stored)
        #expect(snapshot == DeviceRegistrationSnapshot(apnsToken: "abc123", notificationOptIn: true))
    }

    // MARK: - Idempotentlik

    @Test func sameTokenTwiceOnlyPostsOnce() async {
        stubDevicesSuccess()
        let registrar = makeRegistrar()

        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)
        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)

        #expect(apiClient.receivedPaths == ["/devices"])
    }

    @Test func changedTokenPostsAgain() async throws {
        stubDevicesSuccess()
        let registrar = makeRegistrar()

        await registrar.registerToken(DeviceToken(hexString: "aaaa"), optIn: true)
        await registrar.registerToken(DeviceToken(hexString: "bbbb"), optIn: true)

        #expect(apiClient.receivedPaths == ["/devices", "/devices"])
        #expect(try lastBody().apnsToken == "bbbb")
    }

    // MARK: - Eşzamanlılık: TOCTOU (audit MEDIUM — actor reentrancy)

    @Test func eszamanliOptInSonNiyetiKorur() async throws {
        // updateOptIn(false) POST'u askıdayken updateOptIn(true) araya girerse, BAYAT snapshot'la
        // planForOptInChange .skip verip kullanıcının son opt-IN niyetini DÜŞÜRÜR (TOCTOU). Serileştirme
        // ikinci işlemi birincinin save'inden SONRA çalıştırır → son niyet (opt-in) korunur.
        let gate = SendGate()
        let inner = MockAPIClient()
        inner.stub("/devices", with: .success(Data()))
        let store = MockSecureStore()
        try store.setData(
            JSONEncoder().encode(DeviceRegistrationSnapshot(apnsToken: "tok", notificationOptIn: true)),
            forKey: .pushRegistration
        )
        let registrar = LiveDeviceTokenRegistrar(
            apiClient: GatedAPIClient(inner: inner, gate: gate),
            secureStore: store,
            environment: .sandbox,
            logger: MockLogger()
        )

        async let first: Void = registrar.updateOptIn(false)
        await gate.waitForArrival() // birinci POST askıda
        async let second: Void = registrar.updateOptIn(true)
        await gate.open() // birinciyi serbest (bug: bu askı sırasında ikinci reentrant .skip eder)
        _ = await (first, second)

        let saved = try #require(try store.data(forKey: .pushRegistration))
        let snap = try JSONDecoder().decode(DeviceRegistrationSnapshot.self, from: saved)
        #expect(snap.notificationOptIn == true) // son niyet (opt-in) korundu, düşmedi
    }

    // MARK: - İzin değişimi

    @Test func optInFlipReRegistersWithSameToken() async throws {
        stubDevicesSuccess()
        let registrar = makeRegistrar()

        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)
        await registrar.updateOptIn(false)

        #expect(apiClient.receivedPaths == ["/devices", "/devices"])
        let body = try lastBody()
        #expect(body.apnsToken == "abc123")
        #expect(body.notificationOptIn == false)
    }

    @Test func optInChangeWithoutTokenDoesNotPost() async {
        stubDevicesSuccess()
        let registrar = makeRegistrar()

        await registrar.updateOptIn(false)

        #expect(apiClient.receivedPaths.isEmpty)
    }

    // MARK: - Hata → snapshot yazılmaz → yeniden denenir

    @Test func failedRegistrationIsRetriedOnNextCall() async {
        apiClient.stub("/devices", throwing: .network(.offline))
        let registrar = makeRegistrar()

        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)
        #expect(apiClient.receivedPaths == ["/devices"])
        #expect((try? secureStore.data(forKey: .pushRegistration)) == nil)

        // Ağ döndü: aynı token yeniden POST edilir (snapshot yazılmadığı için skip DEĞİL).
        stubDevicesSuccess()
        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)
        #expect(apiClient.receivedPaths == ["/devices", "/devices"])
    }

    // MARK: - deviceId üretimi (Keychain'de yoksa)

    @Test func generatesAndPersistsDeviceIDWhenAbsent() async throws {
        stubDevicesSuccess()
        let registrar = makeRegistrar()

        await registrar.registerToken(DeviceToken(hexString: "abc123"), optIn: true)

        let generated = try #require(try secureStore.string(forKey: .deviceID))
        #expect(!generated.isEmpty)
        #expect(try lastBody().deviceId == generated)
    }
}

// MARK: - Reentrancy testi için kapı (birinci send'i bloklar, ikinciyi geçirir) + gated APIClient

private actor SendGate {
    private var opened = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var arrived = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened {
            return
        } // açıldıktan sonraki send'ler geçer
        arrived = true
        arrivalWaiter?.resume()
        arrivalWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForArrival() async {
        if arrived {
            return
        }
        await withCheckedContinuation { arrivalWaiter = $0 }
    }

    func open() {
        opened = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private final class GatedAPIClient: APIClientProtocol, @unchecked Sendable {
    private let inner: MockAPIClient
    private let gate: SendGate

    init(inner: MockAPIClient, gate: SendGate) {
        self.inner = inner
        self.gate = gate
    }

    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        await gate.wait()
        return try await inner.send(endpoint)
    }
}
