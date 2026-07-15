import Foundation
import Testing
@testable import ProfileKit

/// SS-132 AppleSignInService çekirdek testleri — gerçek Apple UI / `AuthenticationServices` OLMADAN:
/// (c) SAF kimlik-bilgisi doğrulaması (`makeCredential`) ve (b) tek-uçuş continuation reentrancy/stale
/// koruması (`AppleSignInCoordinator`). Hassas alanlar (identityToken/authorizationCode) loglanmaz.
@MainActor
@Suite("SS-132 AppleSignIn çekirdek (kimlik-bilgisi doğrulama + continuation yaşam döngüsü)")
struct AppleSignInServiceTests {
    // MARK: - (c) makeCredential: boş/whitespace identityToken backend'e gitmez

    @Test func makeCredentialRejectsEmptyIdentityToken() {
        // Boş Data → "" identityToken geçerli SAYILMAZ (backend'e boş JWT gitmesin).
        let result = AppleSignInService.makeCredential(
            identityToken: "",
            authorizationCode: "code",
            userIdentifier: "apple-user-1",
            email: nil,
            fullName: nil
        )
        #expect(result.mappedError == .invalidResponse)
    }

    @Test func makeCredentialRejectsWhitespaceIdentityToken() {
        let result = AppleSignInService.makeCredential(
            identityToken: "  \n\t ",
            authorizationCode: nil,
            userIdentifier: "apple-user-1",
            email: nil,
            fullName: nil
        )
        #expect(result.mappedError == .invalidResponse)
    }

    @Test func makeCredentialRejectsNilIdentityToken() {
        let result = AppleSignInService.makeCredential(
            identityToken: nil,
            authorizationCode: nil,
            userIdentifier: "apple-user-1",
            email: nil,
            fullName: nil
        )
        #expect(result.mappedError == .invalidResponse)
    }

    @Test func makeCredentialAcceptsValidTokenAndCleansName() {
        let result = AppleSignInService.makeCredential(
            identityToken: "jwt.header.sig",
            authorizationCode: "auth-code",
            userIdentifier: "apple-user-1",
            email: "j***@example.com",
            fullName: "  Ada Lovelace  "
        )
        guard case let .success(credential) = result else {
            Issue.record("geçerli token success bekleniyordu")
            return
        }
        #expect(credential.identityToken == "jwt.header.sig")
        #expect(credential.authorizationCode == "auth-code")
        #expect(credential.userIdentifier == "apple-user-1")
        #expect(credential.email == "j***@example.com")
        #expect(credential.fullName == "Ada Lovelace") // trim edildi
    }

    @Test func makeCredentialDropsBlankFullName() {
        let result = AppleSignInService.makeCredential(
            identityToken: "jwt",
            authorizationCode: nil,
            userIdentifier: "u",
            email: nil,
            fullName: "   "
        )
        guard case let .success(credential) = result else {
            Issue.record("success bekleniyordu")
            return
        }
        #expect(credential.fullName == nil) // boş ad taşınmaz
    }

    // MARK: - (b) reentrancy: gecikmeli/stale controller callback'i yeni continuation'ı bozmaz

    @Test func staleControllerCallbackDoesNotResumeNewContinuation() async throws {
        let coordinator = AppleSignInCoordinator()
        let ctrlA = NSObject()
        let ctrlB = NSObject()

        // Uçuş A askıya alınır.
        let taskA = Task<AppleCredential, Error> {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AppleCredential, Error>) in
                coordinator.begin(cont, controller: ctrlA)
            }
        }
        #expect(await eventually { coordinator.isSuspended }) // A askıda

        // Reentrancy: uçuş B başlar → A `cancelled` ile biter, aktif controller ctrlB olur.
        let taskB = Task<AppleCredential, Error> {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AppleCredential, Error>) in
                coordinator.begin(cont, controller: ctrlB)
            }
        }
        do {
            _ = try await taskA.value
            Issue.record("A reentrancy'de cancelled olmalıydı")
        } catch {
            #expect((error as? AppleSignInError) == .cancelled)
        }
        #expect(coordinator.isSuspended) // artık B askıda

        // Gecikmeli/stale A callback'i — B'yi ESKİ sonuçla resume ETMEMELİ.
        coordinator.finish(
            from: ctrlA,
            with: .success(AppleCredential(identityToken: "STALE", userIdentifier: "old"))
        )
        // B hâlâ askıda: güncel controller sonucu gelir.
        coordinator.finish(
            from: ctrlB,
            with: .success(AppleCredential(identityToken: "fresh", userIdentifier: "new"))
        )

        let credential = try await taskB.value
        #expect(credential.identityToken == "fresh") // stale sonuç sızmadı
        #expect(credential.userIdentifier == "new")
    }
}

private extension Result where Success == AppleCredential, Failure == Error {
    /// Hata dalını SAF `AppleSignInError`'a indirger (test rahatlığı).
    var mappedError: AppleSignInError? {
        if case let .failure(error) = self {
            return error as? AppleSignInError
        }
        return nil
    }
}
