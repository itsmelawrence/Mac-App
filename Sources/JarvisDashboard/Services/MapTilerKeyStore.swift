import Foundation
import Security

struct MapTilerKeyStore: Sendable {
    private let service = "com.skeemadigital.jarvisdashboard.maptiler"
    private let account = "MapTiler API key"

    func read() -> String? {
        KeychainCache.read(service: service, account: account)
    }

    func save(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw KeyStoreError.emptyKey }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeyStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw KeyStoreError.keychain(status)
        }
        KeychainCache.remember(value, service: service, account: account)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.keychain(status)
        }
        KeychainCache.remember(nil, service: service, account: account)
    }

    enum KeyStoreError: LocalizedError {
        case emptyKey
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyKey: "Enter a MapTiler API key before saving."
            case let .keychain(status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
            }
        }
    }
}

extension Notification.Name {
    static let mapTilerKeyChanged = Notification.Name("jarvis.mapTilerKeyChanged")
}
