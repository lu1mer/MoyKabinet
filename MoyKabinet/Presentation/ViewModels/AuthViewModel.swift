import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var busy = false
    @Published private(set) var providerInFlight: AuthProvider?
    @Published private(set) var cabinets: [AccountCabinet] = []
    @Published private(set) var accountBusy = false
    @Published private(set) var providerAvailability: AuthProviderAvailability?
    @Published private(set) var checkingProviders = false
    @Published private(set) var providerCheckFailed = false
    @Published private(set) var offlineSession = false
    @Published private(set) var verificationEmail: String?
    @Published private(set) var passwordResetEmail: String?
    @Published var error: String?

    private let authenticator: any AuthAuthenticating
    private let repository: any AuthSessionRepository
    private let accountAPI: AccountAPIClient
    private let configuration: AuthConfiguration

    init(
        authenticator: (any AuthAuthenticating)? = nil,
        repository: (any AuthSessionRepository)? = nil,
        accountAPI: AccountAPIClient = AccountAPIClient(),
        configuration: AuthConfiguration = AuthConfiguration()
    ) {
        self.configuration = configuration
        self.accountAPI = accountAPI
        self.authenticator = authenticator ?? DefaultAuthAuthenticator(configuration: configuration)
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments.contains("--auth-ui-testing")
        self.repository = repository ?? (testing ? MemoryAuthSessionRepository() : KeychainAuthSessionRepository())
        session = self.repository.read()
    }

    var isSignedIn: Bool { session != nil }

    func canSignIn(with provider: AuthProvider) -> Bool {
        guard configuration.serverURL != nil else { return false }
        guard providerAvailability?.enabled(provider) == true else { return false }
        switch provider {
        case .email: return providerAvailability?.email == true
        case .apple: return true
        case .google, .yandex:
            return configuration.clientID(for: provider) != nil &&
                (try? configuration.redirect(for: provider)) != nil
        }
    }

    func bootstrap() async {
        guard let current = session, current.isExpired, let refresh = current.refreshToken,
              let server = configuration.serverURL else { return }
        do {
            let renewed = try await accountAPI.refresh(server: server, refreshToken: refresh)
            try repository.write(renewed)
            session = renewed
            offlineSession = false
        } catch AuthError.sessionExpired {
            try? repository.write(nil)
            session = nil
            cabinets = []
            offlineSession = false
        } catch {
            // An existing account remains usable offline; server operations retry when the network returns.
            offlineSession = true
        }
    }

    func login(email: String, password: String) async {
        guard let server = configuration.serverURL, !busy else { error = "Сервер входа не настроен."; return }
        busy = true; defer { busy = false }
        do {
            let value = try await accountAPI.login(server: server, email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            try repository.write(value); session = value; verificationEmail = nil; offlineSession = false; error = nil
            await refreshCabinets()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func register(name: String, email: String, password: String) async {
        guard let server = configuration.serverURL, !busy else { error = "Сервер входа не настроен."; return }
        busy = true; defer { busy = false }
        do {
            let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard try await accountAPI.register(server: server, email: normalized, password: password, displayName: name) else { throw AuthError.invalidResponse }
            verificationEmail = normalized; error = nil
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func confirm(code: String) async {
        guard let server = configuration.serverURL, let email = verificationEmail, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await accountAPI.confirm(server: server, email: email, code: code)
            try repository.write(value); session = value; verificationEmail = nil; offlineSession = false; error = nil
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func requestPasswordReset(email: String) async {
        guard let server = configuration.serverURL, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            try await accountAPI.requestPasswordReset(server: server, email: normalized)
            passwordResetEmail = normalized; error = nil
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func resetPassword(code: String, newPassword: String) async {
        guard let server = configuration.serverURL, let email = passwordResetEmail, !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await accountAPI.resetPassword(server: server, email: email, code: code, newPassword: newPassword)
            passwordResetEmail = nil; error = nil
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func refreshProviderAvailability() async {
        guard let server = configuration.serverURL else {
            providerAvailability = nil
            return
        }
        checkingProviders = true
        defer { checkingProviders = false }
        do {
            providerAvailability = try await accountAPI.availability(server: server)
            providerCheckFailed = false
        } catch {
            providerAvailability = nil
            providerCheckFailed = true
        }
    }

    func signIn(_ provider: AuthProvider) async {
        guard !busy else { return }
        guard provider != .email else { return }
        busy = true
        providerInFlight = provider
        defer { busy = false; providerInFlight = nil }
        do {
            let value = try await authenticator.authenticate(provider: provider)
            try repository.write(value)
            session = value
            error = nil
            await refreshCabinets()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut() async {
        var revokeError: Error?
        if let session, let server = configuration.serverURL {
            do { try await accountAPI.logout(server: server, accessToken: session.accessToken) }
            catch { revokeError = error }
        }
        do {
            try repository.write(nil)
            session = nil
            cabinets = []
            offlineSession = false
            error = revokeError.map { "Сессия на устройстве завершена. Сервер недоступен: \($0.localizedDescription)" }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAccount() async {
        guard let session, let server = configuration.serverURL, !accountBusy else { return }
        accountBusy = true
        defer { accountBusy = false }
        do {
            try await accountAPI.deleteAccount(server: server, accessToken: session.accessToken)
            try repository.write(nil)
            self.session = nil
            cabinets = []
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshCabinets() async {
        guard let session, let server = configuration.serverURL else { return }
        do {
            cabinets = try await accountAPI.cabinets(server: server, accessToken: session.accessToken)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func link(_ credentials: OnlineCredentials) async {
        guard let session, let server = configuration.serverURL else { return }
        guard sameServer(credentials.server, as: server) else {
            error = "Аккаунт настроен для другого сервера. Укажите тот же адрес в онлайн-записи."
            return
        }
        guard !accountBusy else { return }
        accountBusy = true
        defer { accountBusy = false }
        do {
            try await accountAPI.link(server: server, accessToken: session.accessToken, cabinetID: credentials.id, ownerKey: credentials.ownerKey)
            cabinets = try await accountAPI.cabinets(server: server, accessToken: session.accessToken)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func connect(_ cabinet: AccountCabinet, store: CabinetStore, online: OnlineManager) async {
        guard let session, let server = configuration.serverURL else { return }
        guard !accountBusy else { return }
        accountBusy = true
        defer { accountBusy = false }
        do {
            let key = try await accountAPI.issueKey(server: server, accessToken: session.accessToken, cabinetID: cabinet.id)
            await online.connect(server: server.absoluteString, id: key.id, key: key.ownerKey, store: store)
            if online.failed { error = online.message }
            else { error = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sameServer(_ value: String, as expected: URL) -> Bool {
        guard let actual = URL(string: value) else { return false }
        return actual.scheme?.lowercased() == expected.scheme?.lowercased()
            && actual.host?.lowercased() == expected.host?.lowercased()
            && actual.port == expected.port
            && actual.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                == expected.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
