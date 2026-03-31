import Foundation
import Security

/// Simple Keychain wrapper for storing auth tokens securely.
/// Works identically on iOS and macOS via the Security framework.
public enum KeychainHelper {
    private static var serviceName: String {
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            return "\(bundleID).auth"
        }
        return "com.todus.auth"
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
    }

    private static func legacyQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
    }

    private static func logFailure(operation: String, key: String, status: OSStatus) {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown keychain error"
        NSLog("KeychainHelper.\(operation) failed for key '\(key)': \(status) (\(message))")
    }

    public static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query = baseQuery(key: key)
        let legacy = legacyQuery(key: key)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        let legacyDeleteStatus = SecItemDelete(legacy as CFDictionary)
        guard [deleteStatus, legacyDeleteStatus].allSatisfy({ $0 == errSecSuccess || $0 == errSecItemNotFound }) else {
            logFailure(operation: "save", key: key, status: deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound ? deleteStatus : legacyDeleteStatus)
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                logFailure(operation: "save(update)", key: key, status: updateStatus)
                return false
            }
            return true
        default:
            logFailure(operation: "save", key: key, status: addStatus)
            return false
        }
    }

    public static func read(key: String) -> String? {
        if let data = readData(from: baseQuery(key: key)) {
            return String(data: data, encoding: .utf8)
        }
        if let data = readData(from: legacyQuery(key: key)) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    public static func delete(key: String) {
        let query = baseQuery(key: key)
        let legacy = legacyQuery(key: key)
        SecItemDelete(query as CFDictionary)
        SecItemDelete(legacy as CFDictionary)
    }

    // MARK: - Data persistence (for larger blobs like conversation history)
    // Keychain items persist across app reinstalls, unlike UserDefaults.

    public static func saveData(key: String, value: Data) -> Bool {
        let query = baseQuery(key: key)
        let legacy = legacyQuery(key: key)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        let legacyDeleteStatus = SecItemDelete(legacy as CFDictionary)
        guard [deleteStatus, legacyDeleteStatus].allSatisfy({ $0 == errSecSuccess || $0 == errSecItemNotFound }) else {
            logFailure(operation: "saveData", key: key, status: deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound ? deleteStatus : legacyDeleteStatus)
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = value
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: value] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                logFailure(operation: "saveData(update)", key: key, status: updateStatus)
                return false
            }
            return true
        default:
            logFailure(operation: "saveData", key: key, status: addStatus)
            return false
        }
    }

    public static func readData(key: String) -> Data? {
        if let data = readData(from: baseQuery(key: key)) {
            return data
        }
        if let data = readData(from: legacyQuery(key: key)) {
            return data
        }
        return nil
    }

    private static func readData(from query: [String: Any]) -> Data? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }
}
