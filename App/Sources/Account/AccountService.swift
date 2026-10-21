import AuthenticationServices
import Foundation
import LanguifyKit
import Observation

/// Optional Sign in with Apple.
///
/// Signing in identifies the learner to Languify's backend (usage limits and
/// subscription follow them across devices). It is separate from iCloud:
/// vocabulary sync uses the device's iCloud account via CloudKit and works
/// with or without Sign in with Apple. The two are never assumed to match.
@Observable
final class AccountService {
    private(set) var isSignedIn = false
    private(set) var isWorking = false
    var errorMessage: String?

    private let tokens: SessionTokenProvider
    private let api: LanguifyAPIClient

    init(tokens: SessionTokenProvider, api: LanguifyAPIClient) {
        self.tokens = tokens
        self.api = api
        Task { await refresh() }
    }

    func refresh() async {
        isSignedIn = await tokens.isSignedIn
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        // Languify needs no name or email: the Apple user id is enough.
        request.requestedScopes = []
    }

    func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in with Apple didn't complete."
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple didn't return a sign-in token."
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                let token = try await api.linkApple(AppleLinkRequest(identityToken: identityToken))
                await tokens.storeUserToken(token)
                await refresh()
            } catch let error as APIError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = "Couldn't reach Languify to finish signing in."
            }
        }
    }

    func signOut() async {
        await tokens.signOut()
        await refresh()
    }

    /// Deletes server-side records (usage counters, entitlement link) and this
    /// device's identity. Local data is deleted separately by the caller.
    func deleteAccount() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.deleteAccount()
        } catch APIError.notConfigured {
            // No backend in this build, so nothing server-side exists.
        } catch {
            errorMessage = "Couldn't reach Languify to delete server data. Try again when online."
            return false
        }
        await tokens.resetIdentity()
        await refresh()
        return true
    }
}
