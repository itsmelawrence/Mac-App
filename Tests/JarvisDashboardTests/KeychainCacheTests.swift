import Foundation
import Testing
@testable import JarvisDashboard

/// Uses unique, nonexistent services so no real Keychain item is read or written.
struct KeychainCacheTests {
    @Test func rememberedValuesAreServedWithoutAnotherKeychainRead() {
        let service = "jarvis.tests.\(UUID().uuidString)"
        KeychainCache.remember("cached-secret", service: service, account: "a")
        #expect(KeychainCache.read(service: service, account: "a") == "cached-secret")

        KeychainCache.remember(nil, service: service, account: "a")  // What delete() records.
        #expect(KeychainCache.read(service: service, account: "a") == nil)
    }

    @Test func missingItemReadsAsNilAndAccountsAreSeparate() {
        let service = "jarvis.tests.\(UUID().uuidString)"
        #expect(KeychainCache.read(service: service, account: "missing") == nil)
        KeychainCache.remember("one", service: service, account: "first")
        #expect(KeychainCache.read(service: service, account: "second") == nil)
    }
}
