import XCTest
import Security
@testable import Narrateify

@MainActor
final class APIKeyStoreTests: XCTestCase {
    private func temporaryDefaults() -> (UserDefaults, String) {
        let name = "Narrateify-KeyTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testLegacyKeychainInteractionIsDisabledAndRestoredEvenOnFailure() {
        var original: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&original), errSecSuccess)
        let result = Keychain.perform(allowInteraction: false) {
            var during: DarwinBoolean = true
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&during), errSecSuccess)
            XCTAssertFalse(during.boolValue)
            return errSecAuthFailed
        }
        XCTAssertEqual(result, errSecAuthFailed)
        var after: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&after), errSecSuccess)
        XCTAssertEqual(after.boolValue, original.boolValue)
    }

    func testStartupForbidsAuthenticationUI() {
        let request = Keychain.query(account: "test")
        XCTAssertEqual(request[kSecUseAuthenticationUI as String] as? String,
                       kSecUseAuthenticationUIFail as String)
        let explicit = Keychain.query(account: "test", allowInteraction: true)
        XCTAssertEqual(explicit[kSecUseAuthenticationUI as String] as? String,
                       kSecUseAuthenticationUIAllow as String)
    }

    func testLockedStartupDoesNotPromptOrOverwriteLegacyOrSavedKey() {
        let (defaults, name) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("legacy-test-key", forKey: "test")
        var interactions: [Bool] = []
        var writes = 0
        let store = APIKeyStore(account: "test", defaults: defaults,
            read: { _, interactive in interactions.append(interactive); return .locked },
            write: { _, _, _ in writes += 1; return errSecSuccess })
        XCTAssertEqual(interactions, [false])
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(store.needsUnlock)
        XCTAssertTrue(store.value.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "test"), "legacy-test-key")
    }

    func testUnlockIsExplicitAndDenialKeepsSavedKey() {
        let (defaults, name) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var interactions: [Bool] = []
        let store = APIKeyStore(account: "test", defaults: defaults, read: { _, interactive in
            interactions.append(interactive)
            return .locked
        }, write: { _, _, _ in XCTFail("A denied read must never write"); return errSecSuccess })
        store.unlock()
        XCTAssertEqual(interactions, [false, true])
        XCTAssertTrue(store.mayHaveSavedKey)
        XCTAssertTrue(store.needsUnlock)
    }

    func testUnlockLoadsKeyWithoutWritingItBack() {
        let (defaults, name) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = APIKeyStore(account: "test", defaults: defaults,
            read: { _, interactive in interactive ? .value("saved-test-key") : .locked },
            write: { _, _, _ in XCTFail("Loading must not change Keychain"); return errSecSuccess })
        store.unlock()
        XCTAssertEqual(store.value, "saved-test-key")
        XCTAssertFalse(store.needsUnlock)
    }

    func testFailedSavePreservesLoadedKey() {
        let (defaults, name) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = APIKeyStore(account: "test", defaults: defaults,
            read: { _, _ in .value("previous-test-key") },
            write: { _, _, interactive in XCTAssertTrue(interactive); return errSecUserCanceled })
        XCTAssertFalse(store.save("replacement-test-key"))
        XCTAssertEqual(store.value, "previous-test-key")
        XCTAssertTrue(store.mayHaveSavedKey)
    }

    func testFailedSilentMigrationKeepsLegacyValue() {
        let (defaults, name) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("legacy-test-key", forKey: "test")
        let store = APIKeyStore(account: "test", defaults: defaults,
            read: { _, _ in .missing }, write: { _, _, interactive in
                XCTAssertFalse(interactive)
                return errSecInteractionNotAllowed
            })
        XCTAssertEqual(store.value, "legacy-test-key")
        XCTAssertEqual(defaults.string(forKey: "test"), "legacy-test-key")
    }

    func testSuccessfulMigrationRemovesLegacyOnlyAfterSaving() {
        let (defaults, name) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("legacy-test-key", forKey: "test")
        let store = APIKeyStore(account: "test", defaults: defaults,
            read: { _, _ in .missing }, write: { key, _, interactive in
                XCTAssertEqual(key, "legacy-test-key")
                XCTAssertEqual(defaults.string(forKey: "test"), key)
                XCTAssertFalse(interactive)
                return errSecSuccess
            })
        XCTAssertEqual(store.value, "legacy-test-key")
        XCTAssertNil(defaults.string(forKey: "test"))
    }

    func testFailedRemovalKeepsKeyAndEmptySaveDoesNotDelete() {
        let (defaults, name) = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = APIKeyStore(account: "test", defaults: defaults,
            read: { _, _ in .value("saved-test-key") },
            write: { _, _, _ in XCTFail("Empty input must not save"); return errSecSuccess },
            delete: { _, _ in errSecUserCanceled })
        XCTAssertFalse(store.save("  "))
        store.remove()
        XCTAssertEqual(store.value, "saved-test-key")
    }

    func testDeniedReadIsDistinguishedFromMissingKey() {
        XCTAssertEqual(Keychain.decode(status: errSecInteractionNotAllowed, data: nil), .locked)
        XCTAssertEqual(Keychain.decode(status: errSecUserCanceled, data: nil), .locked)
        XCTAssertEqual(Keychain.decode(status: errSecItemNotFound, data: nil), .missing)
    }
}
