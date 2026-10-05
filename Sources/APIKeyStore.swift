import Foundation
import Combine
import Security

/// Failed or denied reads never overwrite a saved key. Interactive access is
/// restricted to deliberate Save, Unlock, and Remove actions in Settings.
@MainActor
final class APIKeyStore: ObservableObject {
    @Published private(set) var value = ""
    @Published private(set) var needsUnlock = false
    @Published private(set) var message = "No saved API key."
    @Published private(set) var mayHaveSavedKey = false

    private let account: String
    private let defaults: UserDefaults
    private let readKey: (String, Bool) -> Keychain.ReadResult
    private let writeKey: (String, String, Bool) -> OSStatus
    private let deleteKey: (String, Bool) -> OSStatus

    init(account: String, defaults: UserDefaults = .standard, loadOnInit: Bool = true,
         read: @escaping (String, Bool) -> Keychain.ReadResult = { Keychain.read(account: $0, allowInteraction: $1) },
         write: @escaping (String, String, Bool) -> OSStatus = { Keychain.set($0, account: $1, allowInteraction: $2) },
         delete: @escaping (String, Bool) -> OSStatus = { Keychain.delete(account: $0, allowInteraction: $1) }) {
        self.account = account
        self.defaults = defaults
        readKey = read
        writeKey = write
        deleteKey = delete
        if loadOnInit { load(allowInteraction: false) }
    }

    var unavailableMessage: String {
        needsUnlock ? "Unlock the saved API key in Settings → Models."
            : "Save an API key in Settings → Models."
    }

    func unlock() { load(allowInteraction: true) }

    private func load(allowInteraction: Bool) {
        switch readKey(account, allowInteraction) {
        case .value(let key):
            value = key
            needsUnlock = false
            mayHaveSavedKey = true
            message = "API key saved in Keychain."
        case .missing:
            // Support old builds without losing the legacy value if migration
            // is denied or the Keychain is unavailable. Never prompt on launch.
            if let legacy = defaults.string(forKey: account), !legacy.isEmpty {
                value = legacy
                mayHaveSavedKey = true
                if writeKey(legacy, account, allowInteraction) == errSecSuccess {
                    defaults.removeObject(forKey: account)
                    needsUnlock = false
                    message = "API key saved in Keychain."
                } else {
                    message = "Existing key kept. Save it to finish moving it to Keychain."
                }
            } else {
                needsUnlock = false
                mayHaveSavedKey = false
                message = "No saved API key."
            }
        case .locked:
            // In particular, do not fall back to writing a legacy key over an
            // inaccessible Keychain item or clear an already-loaded key.
            needsUnlock = value.isEmpty
            mayHaveSavedKey = true
            message = "Saved key needs permission. Local voices work without it."
        case .failure:
            needsUnlock = value.isEmpty
            mayHaveSavedKey = true
            message = "Keychain is unavailable. Your saved key has not been changed."
        }
    }

    @discardableResult
    func save(_ draft: String) -> Bool {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        guard writeKey(key, account, true) == errSecSuccess else {
            message = "Could not save the key. Your previous key has not been changed."
            return false
        }
        value = key
        needsUnlock = false
        mayHaveSavedKey = true
        defaults.removeObject(forKey: account)
        message = "API key saved in Keychain."
        return true
    }

    func remove() {
        let result = deleteKey(account, true)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            message = "Could not remove the key. It has been kept."
            return
        }
        defaults.removeObject(forKey: account)
        value = ""
        needsUnlock = false
        mayHaveSavedKey = false
        message = "No saved API key."
    }
}
