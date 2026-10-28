import Foundation
import Security

/// Process-wide memory of Keychain reads. Each Keychain read can trigger a macOS password
/// prompt, and views read keys on every render, so every item is read at most once per
/// launch. Saves and deletes in the stores keep this cache current.
enum KeychainCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var values: [String: String?] = [:]

    /// Returns the cached value, or reads the generic-password item and caches the result.
    /// "Not found" is cached; other failures (such as a cancelled prompt) are not, so a later read can retry.
    static func read(service: String, account: String) -> String? {
        let key = "\(service)\u{1F}\(account)"
        if let cached = lock.withLock({ values[key] }) { return cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let value = (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        if status == errSecSuccess || status == errSecItemNotFound {
            lock.withLock { values[key] = .some(value) }
        }
        return value
    }

    static func remember(_ value: String?, service: String, account: String) {
        lock.withLock { values["\(service)\u{1F}\(account)"] = .some(value) }
    }

    static func reset() {
        lock.withLock { values.removeAll() }
    }
}
