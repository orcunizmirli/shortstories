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
