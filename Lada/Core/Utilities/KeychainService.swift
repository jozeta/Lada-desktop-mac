import Foundation
import Security

public protocol CredentialStore: Sendable {
    func savePassword(_ password: String, for server: String, account: String) throws
    func loadPassword(for server: String, account: String) throws -> String?
    func deletePassword(for server: String, account: String) throws
}

public final class KeychainCredentialStore: CredentialStore, Sendable {
    private let servicePrefix = "com.lada.desktop.registry"

    public init() {}

    public func savePassword(_ password: String, for server: String, account: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        let service = "\(servicePrefix).\(server)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LadaError(
                category: .permissionError,
                explanation: "Unable to store registry credential in macOS Keychain (OSStatus \(status)).",
                suggestedRemediation: "Ensure macOS Keychain is unlocked and grant Låda permission if prompted.",
                isRetryable: true
            )
        }
    }

    public func loadPassword(for server: String, account: String) throws -> String? {
        let service = "\(servicePrefix).\(server)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    public func deletePassword(for server: String, account: String) throws {
        let service = "\(servicePrefix).\(server)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LadaError(
                category: .permissionError,
                explanation: "Unable to remove registry credential from macOS Keychain (OSStatus \(status)).",
                suggestedRemediation: "Verify Keychain access permissions.",
                isRetryable: true
            )
        }
    }
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func savePassword(_ password: String, for server: String, account: String) throws {
        lock.lock()
        storage["\(server)#\(account)"] = password
        lock.unlock()
    }

    public func loadPassword(for server: String, account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage["\(server)#\(account)"]
    }

    public func deletePassword(for server: String, account: String) throws {
        lock.lock()
        storage.removeValue(forKey: "\(server)#\(account)")
        lock.unlock()
    }
}
