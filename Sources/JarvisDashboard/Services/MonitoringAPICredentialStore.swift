import Foundation
import Security

struct MonitoringAPICredentialStore: Sendable {
    private let service = "com.skeemadigital.jarvisdashboard.monitoring-api"
    private let account = "Laravel Cloud API token"

    func read() -> String? {
        KeychainCache.read(service: service, account: account)
    }

    func save(_ token: String) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw CredentialStoreError.emptyToken }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmedToken.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw CredentialStoreError.keychain(status)
        }
        KeychainCache.remember(trimmedToken, service: service, account: account)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
        KeychainCache.remember(nil, service: service, account: account)
    }

    enum CredentialStoreError: LocalizedError {
        case emptyToken
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyToken:
                "Enter an API token before saving."
            case let .keychain(status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
            }
        }
    }
}
