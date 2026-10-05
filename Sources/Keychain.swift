import Foundation
import Security

/// API keys stay in the original Keychain service. Background operations never
/// display authentication UI; only explicit Settings actions may request it.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.narrateify.Narrateify"

    private static let interactionLock = NSRecursiveLock()

    /// The original app uses the macOS login Keychain, whose older items can
    /// ignore per-query UI flags. Suppress UI for the duration of a silent call,
    /// serialize calls, and restore the previous process policy on every exit.
    static func perform(allowInteraction: Bool, _ operation: () -> OSStatus) -> OSStatus {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        var previous: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess else {
            return errSecInteractionNotAllowed
        }
        guard SecKeychainSetUserInteractionAllowed(allowInteraction) == errSecSuccess else {
            return errSecInteractionNotAllowed
        }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return operation()
    }

    enum ReadResult: Equatable {
        case value(String), missing, locked, failure(OSStatus)
    }

    static func query(account: String, allowInteraction: Bool = false) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseAuthenticationUI as String: allowInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
    }

    static func read(account: String, allowInteraction: Bool = false) -> ReadResult {
        var request = query(account: account, allowInteraction: allowInteraction)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = perform(allowInteraction: allowInteraction) {
            SecItemCopyMatching(request as CFDictionary, &item)
        }
        return decode(status: status, data: item as? Data)
    }

    static func decode(status: OSStatus, data: Data?) -> ReadResult {
        switch status {
        case errSecSuccess:
            guard let data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
                return .failure(errSecDecode)
            }
            return .value(value)
        case errSecItemNotFound: return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: return .locked
        default: return .failure(status)
        }
    }

    static func get(account: String) -> String? {
        if case .value(let value) = read(account: account) { return value }
        return nil
    }

    @discardableResult
    static func set(_ value: String, account: String, allowInteraction: Bool = false) -> OSStatus {
        guard !value.isEmpty else { return delete(account: account, allowInteraction: allowInteraction) }
        let request = query(account: account, allowInteraction: allowInteraction)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return perform(allowInteraction: allowInteraction) {
            let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
            guard status == errSecItemNotFound else { return status }
            return SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    @discardableResult
    static func delete(account: String, allowInteraction: Bool = false) -> OSStatus {
        perform(allowInteraction: allowInteraction) {
            SecItemDelete(query(account: account, allowInteraction: allowInteraction) as CFDictionary)
        }
    }
}
