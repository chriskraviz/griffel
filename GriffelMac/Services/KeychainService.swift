import Foundation
import Security

enum KeychainKey: String, CaseIterable, Codable {
    case openAIAPIKey = "openAIAPIKey"

    var label: String {
        switch self {
        case .openAIAPIKey: return "OpenAI API Key"
        }
    }
}

/// Stores preview credentials in the user's macOS Keychain.
enum KeychainService {
    private static let service = "app.griffel.credentials"
    /// Keychain services used by earlier generations of this app, newest
    /// first — Griffel is derived from Blitztext.
    private static let legacyServices = [
        "app.blitztext.preview.credentials"
    ]

    /// Copies items from a legacy keychain service to the new one, taking the
    /// newest generation that still has the key. Never deletes legacy items
    /// (the uninstaller does that) and skips keys that already exist under the
    /// new service, so repeated calls are safe.
    static func migrateLegacyItemsIfNeeded() {
        for key in KeychainKey.allCases {
            guard load(key: key) == nil,
                  let legacyValue = legacyServices.lazy
                      .compactMap({ load(key: key, service: $0) })
                      .first else {
                continue
            }
            try? save(key: key, value: legacyValue)
        }
    }

    static func deleteLegacyItems() {
        for key in KeychainKey.allCases {
            for legacyService in legacyServices {
                SecItemDelete(baseQuery(for: key, service: legacyService) as CFDictionary)
            }
        }
    }

    static func save(key: KeychainKey, value: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(for: key) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(key: KeychainKey) -> String? {
        load(key: key, service: service)
    }

    private static func load(key: KeychainKey, service: String) -> String? {
        var query = baseQuery(for: key, service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    static func delete(key: KeychainKey) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// Force the next `load` to re-read credentials.
    static func invalidateCache() {
        // Kept for call-site compatibility. Keychain reads do not use an in-memory cache.
    }

    static var isConfigured: Bool {
        load(key: .openAIAPIKey) != nil
    }

    private static func baseQuery(for key: KeychainKey) -> [String: Any] {
        baseQuery(for: key, service: service)
    }

    private static func baseQuery(for key: KeychainKey, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Zugangsdaten konnten nicht im macOS Keychain gespeichert werden. Status: \(status)"
        }
    }
}
