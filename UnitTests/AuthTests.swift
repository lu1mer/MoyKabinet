import XCTest
@testable import MoyKabinet

private final class MockAuthURLProtocol: URLProtocol {
    static var respond: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let respond = Self.respond, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: AuthError.invalidResponse)
            return
        }
        let (status, data) = respond(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: AuthError.invalidResponse)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AuthTests: XCTestCase {
    private struct StubAuthenticator: AuthAuthenticating {
        let result: Result<AuthSession, AuthError>

        func authenticate(provider: AuthProvider) async throws -> AuthSession {
            try result.get()
        }
    }

    private var offlineConfiguration: AuthConfiguration {
        AuthConfiguration(serverURL: nil, googleClientID: nil, yandexClientID: nil)
    }

    private var serverConfiguration: AuthConfiguration {
        AuthConfiguration(serverURL: URL(string: "https://auth.example.test"), googleClientID: nil, yandexClientID: nil)
    }

    private func mockedAPIClient() -> (AccountAPIClient, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return (AccountAPIClient(session: session), session)
    }

    private func session(provider: AuthProvider = .google) -> AuthSession {
        AuthSession(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "user-1", provider: provider, email: "master@example.com", displayName: "Мастер", avatarURL: nil)
        )
    }

    @MainActor
    func testSuccessfulSignInPersistsSessionForNextLaunch() async {
        let expected = session()
        let repository = MemoryAuthSessionRepository()
        let model = AuthViewModel(
            authenticator: StubAuthenticator(result: .success(expected)),
            repository: repository,
            configuration: offlineConfiguration
        )

        await model.signIn(.google)

        XCTAssertEqual(model.session, expected)
        XCTAssertEqual(repository.read(), expected)
        XCTAssertTrue(model.isSignedIn)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.providerInFlight)
        XCTAssertNil(model.error)

        let relaunched = AuthViewModel(
            authenticator: StubAuthenticator(result: .failure(.serverUnavailable)),
            repository: repository,
            configuration: offlineConfiguration
        )
        XCTAssertEqual(relaunched.session, expected)
    }

    @MainActor
    func testFailedProviderLeavesNoSession() async {
        let repository = MemoryAuthSessionRepository()
        let model = AuthViewModel(
            authenticator: StubAuthenticator(result: .failure(.serverUnavailable)),
            repository: repository,
            configuration: offlineConfiguration
        )

        await model.signIn(.yandex)

        XCTAssertNil(model.session)
        XCTAssertNil(repository.read())
        XCTAssertFalse(model.isSignedIn)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.providerInFlight)
        XCTAssertEqual(model.error, AuthError.serverUnavailable.errorDescription)
    }

    @MainActor
    func testSignOutClearsLocalSession() async {
        let repository = MemoryAuthSessionRepository(value: session(provider: .apple))
        let model = AuthViewModel(
            authenticator: StubAuthenticator(result: .failure(.serverUnavailable)),
            repository: repository,
            configuration: offlineConfiguration
        )
        XCTAssertTrue(model.isSignedIn)

        await model.signOut()

        XCTAssertNil(model.session)
        XCTAssertNil(repository.read())
        XCTAssertFalse(model.isSignedIn)
        XCTAssertTrue(model.cabinets.isEmpty)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testDeleteAccountClearsPersistedSessionAfterServerSuccess() async {
        let expected = session(provider: .apple)
        let repository = MemoryAuthSessionRepository(value: expected)
        let (api, urlSession) = mockedAPIClient()
        defer { MockAuthURLProtocol.respond = nil; urlSession.invalidateAndCancel() }
        MockAuthURLProtocol.respond = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/me")
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(expected.accessToken)")
            return (200, Data(#"{"deleted":true}"#.utf8))
        }
        let model = AuthViewModel(
            authenticator: StubAuthenticator(result: .failure(.serverUnavailable)),
            repository: repository,
            accountAPI: api,
            configuration: serverConfiguration
        )

        await model.deleteAccount()

        XCTAssertNil(model.session)
        XCTAssertNil(repository.read())
        XCTAssertFalse(model.isSignedIn)
        XCTAssertFalse(model.accountBusy)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testDeleteAccountServerFailureKeepsPersistedSession() async {
        let expected = session(provider: .yandex)
        let repository = MemoryAuthSessionRepository(value: expected)
        let (api, urlSession) = mockedAPIClient()
        defer { MockAuthURLProtocol.respond = nil; urlSession.invalidateAndCancel() }
        MockAuthURLProtocol.respond = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/me")
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (503, Data(#"{"error":"Сервер временно недоступен"}"#.utf8))
        }
        let model = AuthViewModel(
            authenticator: StubAuthenticator(result: .failure(.serverUnavailable)),
            repository: repository,
            accountAPI: api,
            configuration: serverConfiguration
        )

        await model.deleteAccount()

        XCTAssertEqual(model.session, expected)
        XCTAssertEqual(repository.read(), expected)
        XCTAssertTrue(model.isSignedIn)
        XCTAssertFalse(model.accountBusy)
        XCTAssertEqual(model.error, "Сервер временно недоступен")
    }
}
