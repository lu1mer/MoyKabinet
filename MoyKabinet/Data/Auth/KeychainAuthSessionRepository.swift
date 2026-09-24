import Foundation
import Security

struct KeychainAuthSessionRepository: AuthSessionRepository {
    private static let service = "com.moykabinet.auth.session"

    func read() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func write(_ value: AuthSession?) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service
        ]
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AuthError.message("Не удалось завершить сессию.")
            }
            return
        }
        let encoded = try JSONEncoder().encode(value)
        let protectedValue: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, protectedValue as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = encoded
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw AuthError.message("Не удалось сохранить сессию в связке ключей.")
            }
        } else if update != errSecSuccess {
            throw AuthError.message("Не удалось обновить сессию.")
        }
    }
}

final class MemoryAuthSessionRepository: AuthSessionRepository {
    private var value: AuthSession?
    init(value: AuthSession? = nil) { self.value = value }
    func read() -> AuthSession? { value }
    func write(_ value: AuthSession?) throws { self.value = value }
}
