import Foundation
import Security

public enum SecretStorageError: Error, LocalizedError, Equatable {
    case keychain(OSStatus)
    case invalidSecret

    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain에 접근할 수 없습니다 (\(status))."
        case .invalidSecret: "저장된 키의 형식이 올바르지 않습니다."
        }
    }
}

protocol SecretBackend: Sendable {
    func read(service: String, account: String) throws -> Data?
    func save(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct SystemKeychainBackend: SecretBackend {
    private func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func read(service: String, account: String) throws -> Data? {
        var request = query(service: service, account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStorageError.keychain(status) }
        guard let data = result as? Data else { throw SecretStorageError.invalidSecret }
        return data
    }

    func save(_ data: Data, service: String, account: String) throws {
        let request = query(service: service, account: account)
        let updated = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw SecretStorageError.keychain(updated) }
        var item = request
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw SecretStorageError.keychain(added) }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStorageError.keychain(status)
        }
    }
}

public enum KeychainSecrets {
    static let service = "app.opennotype.provider-secrets"

    public static func save(_ value: String, for provider: AIProvider) throws {
        try save(value, for: provider, backend: SystemKeychainBackend())
    }

    public static func read(for provider: AIProvider) throws -> String? {
        try read(for: provider, backend: SystemKeychainBackend())
    }

    public static func delete(for provider: AIProvider) throws {
        try delete(for: provider, backend: SystemKeychainBackend())
    }

    static func save(_ value: String, for provider: AIProvider, backend: any SecretBackend) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecretStorageError.invalidSecret
        }
        try backend.save(Data(value.utf8), service: service, account: provider.rawValue)
    }

    static func read(for provider: AIProvider, backend: any SecretBackend) throws -> String? {
        guard let data = try backend.read(service: service, account: provider.rawValue) else { return nil }
        guard let result = String(data: data, encoding: .utf8) else { throw SecretStorageError.invalidSecret }
        return result
    }

    static func delete(for provider: AIProvider, backend: any SecretBackend) throws {
        try backend.delete(service: service, account: provider.rawValue)
    }
}
