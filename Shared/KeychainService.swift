// KeychainService.swift
// Ai4Poors - Secure credential storage for API Skills
//
// Stores API keys and tokens in the iOS Keychain with app group
// sharing so extensions can also access credentials.

import Foundation
import Security

enum KeychainService {

    private static let accessGroup = AppGroupConstants.suiteName

    // MARK: - Save

    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first to avoid duplicate errors
        delete(key: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.example.ai4poors.skills",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        #if !os(macOS)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Read

    static func read(key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.example.ai4poors.skills",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        #if !os(macOS)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    @discardableResult
    static func delete(key: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.example.ai4poors.skills"
        ]

        #if !os(macOS)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Check Existence

    static func exists(key: String) -> Bool {
        read(key: key) != nil
    }
}
