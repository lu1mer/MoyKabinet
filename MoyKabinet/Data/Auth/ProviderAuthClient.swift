import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct AuthAPIClient {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func exchangeCode(
        server: URL,
        provider: AuthProvider,
        code: String,
        verifier: String,
        redirectURI: String
    ) async throws -> AuthSession {
        try await request(server: server, path: "api/auth/exchange", body: [
            "provider": provider.rawValue,
            "code": code,
            "codeVerifier": verifier,
            "redirectURI": redirectURI
        ], expectedProvider: provider)
    }

    func exchangeApple(
        server: URL,
        identityToken: Data,
        authorizationCode: Data?,
        userIdentifier: String,
        email: String?,
        displayName: String?
    ) async throws -> AuthSession {
        var body: [String: Any] = [
            "provider": AuthProvider.apple.rawValue,
            "identityToken": identityToken.base64EncodedString(),
            "userIdentifier": userIdentifier
        ]
        if let authorizationCode { body["authorizationCode"] = authorizationCode.base64EncodedString() }
        if let email { body["email"] = email }
        if let displayName { body["displayName"] = displayName }
        return try await request(server: server, path: "api/auth/apple", body: body, expectedProvider: .apple)
    }

    private func request(server: URL, path: String, body: [String: Any], expectedProvider: AuthProvider) async throws -> AuthSession {
        let url = server.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw AuthError.serverUnavailable }
            guard (200..<300).contains(response.statusCode) else {
                let serverMessage = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String).map { String($0.prefix(240)) }
                if response.statusCode == 503 { throw AuthError.message(serverMessage ?? "Провайдер пока не настроен на сервере.") }
                throw AuthError.message(serverMessage ?? "Сервер отклонил вход (\(response.statusCode)).")
            }
            return try Self.decodeSession(data, expectedProvider: expectedProvider)
        } catch let error as AuthError {
            throw error
        } catch is CancellationError {
            throw AuthError.cancelled
        } catch let error as URLError {
            throw error.code == .cancelled ? AuthError.cancelled : AuthError.serverUnavailable
        } catch {
            throw AuthError.serverUnavailable
        }
    }

    static func decodeSession(_ data: Data, expectedProvider: AuthProvider?) throws -> AuthSession {
        struct Response: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Double?
            let expiresIn: Double?
            let user: AuthUser
        }
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            let expiry = response.expiresAt.map(Date.init(timeIntervalSince1970:))
                ?? response.expiresIn.map { Date().addingTimeInterval($0) }
            guard !response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !response.user.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  expectedProvider.map({ response.user.provider == $0 }) ?? true,
                  expiry.map({ $0.timeIntervalSince1970.isFinite && $0 > .now }) ?? true else {
                throw AuthError.invalidResponse
            }
            return AuthSession(accessToken: response.accessToken, refreshToken: response.refreshToken, expiresAt: expiry, user: response.user)
        } catch {
            throw AuthError.invalidResponse
        }
    }
}

@MainActor
final class DefaultAuthAuthenticator: AuthAuthenticating {
    private let configuration: AuthConfiguration
    private let api: AuthAPIClient
    private var appleCoordinator: AppleSignInCoordinator?
    private var webCoordinator: WebAuthSessionCoordinator?

    init(configuration: AuthConfiguration = AuthConfiguration(), api: AuthAPIClient = AuthAPIClient()) {
        self.configuration = configuration
        self.api = api
    }

    func authenticate(provider: AuthProvider) async throws -> AuthSession {
        guard let server = configuration.serverURL else { throw AuthError.providerNotConfigured(provider) }
        switch provider {
        case .email:
            throw AuthError.invalidCallback
        case .apple:
            let coordinator = AppleSignInCoordinator()
            appleCoordinator = coordinator
            defer { appleCoordinator = nil }
            let credential = try await coordinator.authenticate()
            return try await api.exchangeApple(
                server: server,
                identityToken: credential.identityToken,
                authorizationCode: credential.authorizationCode,
                userIdentifier: credential.userIdentifier,
                email: credential.email,
                displayName: credential.displayName
            )
        case .google, .yandex:
            guard let clientID = configuration.clientID(for: provider) else {
                throw AuthError.providerNotConfigured(provider)
            }
            let verifier = try secureRandomURLSafeString(byteCount: 32)
            let state = UUID().uuidString + UUID().uuidString
            let callback = try configuration.redirect(for: provider)
            let authorizeURL = try makeAuthorizeURL(provider: provider, clientID: clientID, state: state, verifier: verifier, redirectURI: callback.uri)
            let coordinator = WebAuthSessionCoordinator()
            webCoordinator = coordinator
            defer { webCoordinator = nil }
            let result = try await coordinator.authenticate(url: authorizeURL, expectedRedirect: callback.uri, callbackScheme: callback.scheme)
            guard result.state == state, let code = result.code else { throw AuthError.invalidCallback }
            return try await api.exchangeCode(server: server, provider: provider, code: code, verifier: verifier, redirectURI: callback.uri)
        }
    }

    private func secureRandomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw AuthError.message("Не удалось безопасно начать вход. Попробуйте ещё раз.") }
        return Data(bytes).base64URLString
    }

    private func makeAuthorizeURL(provider: AuthProvider, clientID: String, state: String, verifier: String, redirectURI: String) throws -> URL {
        let endpoint: String
        let scope: String
        switch provider {
        case .email:
            throw AuthError.invalidCallback
        case .google:
            endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
            scope = "openid email profile"
        case .yandex:
            endpoint = "https://oauth.yandex.ru/authorize"
            scope = "login:email login:info"
        case .apple:
            throw AuthError.invalidCallback
        }
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: verifier.sha256Base64URL),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else { throw AuthError.invalidCallback }
        return url
    }
}

private struct WebAuthResult {
    let code: String?
    let state: String?
}

private final class WebAuthSessionCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<WebAuthResult, Error>?

    func authenticate(url: URL, expectedRedirect: String, callbackScheme: String) async throws -> WebAuthResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WebAuthResult, Error>) in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                guard let self else { return }
                self.session = nil
                if let error {
                    self.finish(.failure((error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue ? AuthError.cancelled : AuthError.invalidCallback))
                    return
                }
                guard let callback,
                      let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                      let expected = URLComponents(string: expectedRedirect),
                      components.scheme?.lowercased() == expected.scheme?.lowercased(),
                      components.host?.lowercased() == expected.host?.lowercased(),
                      components.path == expected.path else {
                    self.finish(.failure(AuthError.invalidCallback)); return
                }
                var values: [String: String] = [:]
                for item in components.queryItems ?? [] {
                    guard values[item.name] == nil, let value = item.value else {
                        self.finish(.failure(AuthError.invalidCallback)); return
                    }
                    values[item.name] = value
                }
                if let oauthError = values["error"] {
                    self.finish(.failure(oauthError == "access_denied" ? AuthError.cancelled : AuthError.message("Провайдер не подтвердил вход. Попробуйте ещё раз.")))
                    return
                }
                guard let code = values["code"], !code.isEmpty, let state = values["state"], !state.isEmpty else {
                    self.finish(.failure(AuthError.invalidCallback)); return
                }
                self.finish(.success(WebAuthResult(code: code, state: state)))
            }
            self.session = session
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            guard session.start() else {
                self.finish(.failure(AuthError.serverUnavailable))
                return
            }
        }
    }

    private func finish(_ result: Result<WebAuthResult, Error>) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow(frame: .zero)
    }
}

private struct AppleCredential {
    let identityToken: Data
    let authorizationCode: Data?
    let userIdentifier: String
    let email: String?
    let displayName: String?
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<AppleCredential, Error>?

    func authenticate() async throws -> AppleCredential {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppleCredential, Error>) in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken else {
            finish(.failure(AuthError.invalidResponse)); return
        }
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        finish(.success(AppleCredential(
            identityToken: identityToken,
            authorizationCode: credential.authorizationCode,
            userIdentifier: credential.user,
            email: credential.email,
            displayName: name.isEmpty ? nil : name
        )))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        finish(.failure(nsError.code == ASAuthorizationError.canceled.rawValue ? AuthError.cancelled : AuthError.message("Apple не подтвердил вход. Попробуйте ещё раз.")))
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        controller = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow(frame: .zero)
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var sha256Base64URL: String {
        Data(utf8).sha256.base64URLString
    }
}

private extension Data {
    var sha256: Data { Data(SHA256.hash(data: self)) }
}
