import Foundation
import Security

protocol OnlineCredentialRepository {
    func read() -> OnlineCredentials?
    func write(_ value: OnlineCredentials?) throws
}

struct KeychainCredentialRepository: OnlineCredentialRepository {
    private static let service = "com.moykabinet.online"
    func read() -> OnlineCredentials? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OnlineCredentials.self, from: data)
    }
    func write(_ value: OnlineCredentials?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service]
        guard let value else { SecItemDelete(query as CFDictionary); return }
        let encoded = try JSONEncoder().encode(value)
        let protectedValue: [String: Any] = [kSecValueData as String: encoded, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, protectedValue as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = encoded
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw DataIssue.invalid("Не удалось сохранить ключ в связке ключей.") }
        } else if update != errSecSuccess { throw DataIssue.invalid("Не удалось обновить ключ доступа.") }
    }
}

final class MemoryCredentialRepository: OnlineCredentialRepository {
    private var value: OnlineCredentials?
    func read() -> OnlineCredentials? { value }
    func write(_ value: OnlineCredentials?) throws { self.value = value }
}
