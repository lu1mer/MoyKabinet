import Foundation

/// Providers supported by the account layer. Provider SDKs are deliberately
/// hidden behind `AuthAuthenticating`, so the rest of the app does not depend
/// on a vendor-specific implementation.
enum AuthProvider: String, Codable, CaseIterable, Identifiable {
    case email
    case apple
    case google
    case yandex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .email: return "Email"
        case .apple: return "Apple"
        case .google: return "Google"
        case .yandex: return "Яндекс"
        }
    }

    var systemImage: String {
        switch self {
        case .email: return "envelope.fill"
        case .apple: return "apple.logo"
        case .google: return "g.circle.fill"
        case .yandex: return "y.circle.fill"
        }
    }
}

struct AuthUser: Codable, Equatable, Identifiable {
    let id: String
    let provider: AuthProvider
    var email: String?
    var displayName: String?
    var avatarURL: URL?
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    let user: AuthUser

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= .now.addingTimeInterval(30)
    }
}

protocol AuthSessionRepository {
    func read() -> AuthSession?
    func write(_ value: AuthSession?) throws
}

protocol AuthAuthenticating {
    func authenticate(provider: AuthProvider) async throws -> AuthSession
}

enum AuthError: LocalizedError, Equatable {
    case cancelled
    case providerNotConfigured(AuthProvider)
    case invalidCallback
    case serverUnavailable
    case invalidResponse
    case sessionExpired
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Авторизация отменена."
        case .providerNotConfigured(let provider):
            return "Вход через \(provider.title) ещё не настроен на сервере. Добавьте OAuth-реквизиты в окружение сервера."
        case .invalidCallback: return "Не удалось подтвердить ответ провайдера. Попробуйте ещё раз."
        case .serverUnavailable: return "Сервер авторизации недоступен. Локальные данные приложения сохранены."
        case .invalidResponse: return "Сервер вернул некорректный ответ авторизации."
        case .sessionExpired: return "Сессия истекла. Войдите снова."
        case .message(let value): return value
        }
    }
}
