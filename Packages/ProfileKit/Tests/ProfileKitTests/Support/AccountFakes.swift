import AppFoundation
import Foundation
@testable import ProfileKit

// MARK: - Ortak test hatası

struct TestFailure: Error, Equatable {}

extension AppleCredential {
    /// İkinci-giriş kalıbı: Apple email/fullName yalnız ilk seferde döner → burada nil (backend saklar).
    static let stub = AppleCredential(identityToken: "jwt.header.sig", userIdentifier: "apple-user-1")
}

extension GoogleCredential {
    static let stub = GoogleCredential(idToken: "google.id.token", authorizationCode: "g-auth-code")
}

extension EmailCredential {
    static let stub = EmailCredential(email: "user@example.com", verificationToken: "vtok_1")
}

// MARK: - Sign in with Apple portu fake'i (gerçek AuthenticationServices YOK)

final class FakeAppleSignIn: AppleSignInProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<AppleCredential, Error>
    private var calls = 0

    init(_ result: Result<AppleCredential, Error> = .success(.stub)) {
        self.result = result
    }

    func setResult(_ newValue: Result<AppleCredential, Error>) {
        lock.withLock { result = newValue }
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func requestCredential() async throws -> AppleCredential {
        try lock.withLock {
            calls += 1
            return try result.get()
        }
    }
}

// MARK: - Google Sign-In portu fake'i (gerçek Google SDK YOK)

final class FakeGoogleSignIn: GoogleSignInProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<GoogleCredential, Error>
    private var calls = 0

    init(_ result: Result<GoogleCredential, Error> = .success(.stub)) {
        self.result = result
    }

    func setResult(_ newValue: Result<GoogleCredential, Error>) {
        lock.withLock { result = newValue }
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func signIn() async throws -> GoogleCredential {
        try lock.withLock {
            calls += 1
            return try result.get()
        }
    }
}

// MARK: - E-posta bağlama portu fake'i (gerçek /auth/email/* YOK)

final class FakeEmailLink: EmailLinkProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<EmailCredential, Error>
    private var calls = 0
    private var lastInput: (email: String, password: String)?

    init(_ result: Result<EmailCredential, Error> = .success(.stub)) {
        self.result = result
    }

    func setResult(_ newValue: Result<EmailCredential, Error>) {
        lock.withLock { result = newValue }
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    var lastEmail: String? {
        lock.withLock { lastInput?.email }
    }

    var lastPassword: String? {
        lock.withLock { lastInput?.password }
    }

    func linkCredential(email: String, password: String) async throws -> EmailCredential {
        try lock.withLock {
            calls += 1
            lastInput = (email, password)
            return try result.get()
        }
    }
}

// MARK: - Hesap bağlama backend portu fake'i (sağlayıcı-bağımsız)

final class FakeAccountLinking: AccountLinkingServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var linkResult: Result<AccountLinkOutcome, Error>
    private var switchResult: Result<AccountSummary, Error>
    private var linkCalls = 0
    private var switchCalls = 0
    private var linkedProviders: [AuthProvider] = []

    static let linkedApple = AccountSummary(kind: .linked(provider: .apple))

    init(
        link: Result<AccountLinkOutcome, Error> = .success(.linked(FakeAccountLinking.linkedApple)),
        switchTo: Result<AccountSummary, Error> = .success(FakeAccountLinking.linkedApple)
    ) {
        linkResult = link
        switchResult = switchTo
    }

    func setLink(_ newValue: Result<AccountLinkOutcome, Error>) {
        lock.withLock { linkResult = newValue }
    }

    func setSwitch(_ newValue: Result<AccountSummary, Error>) {
        lock.withLock { switchResult = newValue }
    }

    var linkCallCount: Int {
        lock.withLock { linkCalls }
    }

    var switchCallCount: Int {
        lock.withLock { switchCalls }
    }

    /// `link` çağrılarında taşınan sağlayıcılar (sırayla) — sağlayıcı-bağımsız yolun doğru `provider`
    /// alanını taşıdığını doğrular.
    var linkedProviderSequence: [AuthProvider] {
        lock.withLock { linkedProviders }
    }

    func link(_ credential: LinkCredential) async throws -> AccountLinkOutcome {
        try lock.withLock {
            linkCalls += 1
            linkedProviders.append(credential.provider)
            return try linkResult.get()
        }
    }

    func switchToExistingAccount(_: AccountLinkConflict) async throws -> AccountSummary {
        try lock.withLock {
            switchCalls += 1
            return try switchResult.get()
        }
    }
}

// MARK: - Hesap silme + veri talebi portu fake'i

final class FakeAccountDeletion: AccountDeletionServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var deletionResult: Result<AccountDeletionReceipt, Error>
    private var exportResult: Result<DataExportReceipt, Error>
    private var deletionCalls = 0
    private var exportCalls = 0

    init(
        deletion: Result<AccountDeletionReceipt, Error> =
            .success(AccountDeletionReceipt(undoDeadline: nil, requiresStoreSubscriptionCancellation: false)),
        export: Result<DataExportReceipt, Error> = .success(DataExportReceipt(deliveryEmailMasked: nil))
    ) {
        deletionResult = deletion
        exportResult = export
    }

    func setDeletion(_ newValue: Result<AccountDeletionReceipt, Error>) {
        lock.withLock { deletionResult = newValue }
    }

    func setExport(_ newValue: Result<DataExportReceipt, Error>) {
        lock.withLock { exportResult = newValue }
    }

    var deletionCallCount: Int {
        lock.withLock { deletionCalls }
    }

    var exportCallCount: Int {
        lock.withLock { exportCalls }
    }

    func requestDeletion() async throws -> AccountDeletionReceipt {
        try lock.withLock {
            deletionCalls += 1
            return try deletionResult.get()
        }
    }

    func requestDataDownload() async throws -> DataExportReceipt {
        try lock.withLock {
            exportCalls += 1
            return try exportResult.get()
        }
    }
}

// MARK: - Delegate spy'ları

@MainActor
final class HesapBaglamaDelegateSpy: HesapBaglamaDelegate {
    var linked: [AccountSummary] = []
    var dismissed = 0

    func hesapBaglamaDidLink(_ account: AccountSummary) {
        linked.append(account)
    }

    func hesapBaglamaRequestsDismiss() {
        dismissed += 1
    }
}

@MainActor
final class HesapSilmeDelegateSpy: HesapSilmeDelegate {
    var completed: [AccountDeletionReceipt] = []
    var dismissed = 0

    func hesapSilmeDidComplete(_ receipt: AccountDeletionReceipt) {
        completed.append(receipt)
    }

    func hesapSilmeRequestsDismiss() {
        dismissed += 1
    }
}
