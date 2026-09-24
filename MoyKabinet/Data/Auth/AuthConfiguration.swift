import Foundation

struct AuthConfiguration {
    let serverURL: URL?
    let googleClientID: String?
    let yandexClientID: String?
    let callbackScheme: String
    private let registeredSchemes: Set<String>

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        serverURL = Self.validServerURL((info["AUTH_SERVER_URL"] as? String)?.configuredValue)
        googleClientID = (info["AUTH_GOOGLE_CLIENT_ID"] as? String)?.configuredValue
        yandexClientID = (info["AUTH_YANDEX_CLIENT_ID"] as? String)?.configuredValue
        callbackScheme = (info["AUTH_CALLBACK_SCHEME"] as? String)?.configuredValue ?? "moykabinet"
        registeredSchemes = Self.schemes(in: info)
    }

    init(serverURL: URL?, googleClientID: String?, yandexClientID: String?, callbackScheme: String = "moykabinet", registeredSchemes: Set<String>? = nil) {
        self.serverURL = Self.validServerURL(serverURL?.absoluteString)
        self.googleClientID = googleClientID?.configuredValue
        self.yandexClientID = yandexClientID?.configuredValue
        self.callbackScheme = callbackScheme.configuredValue ?? "moykabinet"
        self.registeredSchemes = registeredSchemes ?? Self.schemes(in: Bundle.main.infoDictionary ?? [:])
    }

    func clientID(for provider: AuthProvider) -> String? {
        switch provider {
        case .email: return nil
        case .apple: return "com.moykabinet.app"
        case .google: return googleClientID
        case .yandex: return yandexClientID
        }
    }

    func redirect(for provider: AuthProvider) throws -> (uri: String, scheme: String) {
        let scheme: String
        let uri: String
        switch provider {
        case .email:
            throw AuthError.invalidCallback
        case .google:
            guard let clientID = googleClientID, let configured = Self.googleScheme(for: clientID) else {
                throw AuthError.message("Укажите корректный iOS Client ID Google в настройках сборки.")
            }
            scheme = configured
            uri = "\(scheme):/oauth/google"
        case .yandex:
            scheme = callbackScheme
            uri = "\(scheme)://oauth/yandex"
        case .apple:
            throw AuthError.invalidCallback
        }
        guard registeredSchemes.contains(scheme.lowercased()) else {
            throw AuthError.message("Схема возврата \(scheme) не зарегистрирована в настройках приложения.")
        }
        return (uri, scheme)
    }

    private static func googleScheme(for clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty, prefix.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }

    private static func schemes(in info: [String: Any]) -> Set<String> {
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return Set(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() })
    }

    private static func validServerURL(_ string: String?) -> URL? {
        guard let value = string?.configuredValue, let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(),
              components.user == nil, components.password == nil, components.query == nil,
              components.fragment == nil, components.path.isEmpty || components.path == "/",
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) else { return nil }
        return components.url
    }
}

private extension String {
    var configuredValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$("), !value.contains("${") else { return nil }
        return value
    }
}
