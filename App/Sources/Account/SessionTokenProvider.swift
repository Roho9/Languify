import Foundation
import LanguifyKit

/// Provides bearer tokens for the Languify backend.
///
/// Every install gets an anonymous guest identity, so no account is needed.
/// After Sign in with Apple the backend issues a user token (and merges the
/// guest's usage and entitlement into it); that token is preferred while valid.
actor SessionTokenProvider: AuthTokenProviding {
    private let keychain: KeychainStore
    private let registrar: LanguifyAPIClient
    private var inflight: Task<TokenResponse, Error>?

    private enum Account {
        static let installID = "install-id"
        static let installToken = "install-token"
        static let userToken = "user-token"
    }

    init(keychain: KeychainStore = KeychainStore(), baseURL: URL?) {
        self.keychain = keychain
        self.registrar = LanguifyAPIClient(baseURL: baseURL, tokens: nil)
    }

    var installID: String {
        if let existing = keychain.string(for: Account.installID) { return existing }
        let id = UUID().uuidString
        keychain.set(id, for: Account.installID)
        return id
    }

    var isSignedIn: Bool { validToken(Account.userToken) != nil }

    var userID: String? { stored(Account.userToken)?.userId }

    func currentToken() async throws -> String {
        if let user = validToken(Account.userToken) { return user.token }
        if let install = validToken(Account.installToken) { return install.token }
        return try await registerInstall().token
    }

    func invalidate() async {
        keychain.remove(Account.installToken)
        if let user = stored(Account.userToken), user.expiresAt <= Date() {
            keychain.remove(Account.userToken)
        }
    }

    func storeUserToken(_ token: TokenResponse) {
        store(token, Account.userToken)
    }

    func signOut() {
        keychain.remove(Account.userToken)
    }

    /// Forgets every identity on this device. A new guest id is created on next use.
    func resetIdentity() {
        keychain.remove(Account.userToken)
        keychain.remove(Account.installToken)
        keychain.remove(Account.installID)
    }

    private func registerInstall() async throws -> TokenResponse {
        if let inflight { return try await inflight.value }
        let id = installID
        let task = Task { try await registrar.registerInstall(InstallRegistration(installId: id)) }
        inflight = task
        defer { inflight = nil }
        let token = try await task.value
        store(token, Account.installToken)
        return token
    }

    private func validToken(_ account: String) -> TokenResponse? {
        guard let token = stored(account), token.expiresAt > Date().addingTimeInterval(60) else { return nil }
        return token
    }

    private func stored(_ account: String) -> TokenResponse? {
        guard let data = keychain.data(for: account) else { return nil }
        return try? LanguifyAPIClient.makeDecoder().decode(TokenResponse.self, from: data)
    }

    private func store(_ token: TokenResponse, _ account: String) {
        guard let data = try? LanguifyAPIClient.makeEncoder().encode(token) else { return }
        keychain.set(data, for: account)
    }
}
