import Foundation
import Security

struct MonitoringSiteCredentialStore: Sendable {
    private let service = "com.skeemadigital.jarvisdashboard.monitoring-site"

    func read(projectID: UUID) -> String? {
        read(account: projectID.uuidString)
    }

    func save(_ token: String, projectID: UUID) throws {
        try save(token, account: projectID.uuidString)
    }

    func delete(projectID: UUID) throws {
        try delete(account: projectID.uuidString)
    }

    private func read(account: String) -> String? {
        KeychainCache.read(service: service, account: account)
    }

    private func save(_ token: String, account: String) throws {
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
            guard addStatus == errSecSuccess else { throw CredentialStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw CredentialStoreError.keychain(status)
        }
        KeychainCache.remember(trimmedToken, service: service, account: account)
    }

    private func delete(account: String) throws {
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
}

struct MonitoringAdminCredentialStore: Sendable {
    private let store = MonitoringSiteCredentialStore()
    private let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func read() -> String? { store.read(projectID: accountID) }
    func save(_ token: String) throws { try store.save(token, projectID: accountID) }
    func delete() throws { try store.delete(projectID: accountID) }
}

private enum CredentialStoreError: LocalizedError {
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
