import Foundation
import Security

enum DeepSeekAPIKeyStore {
    private static let service = "com.waykingah.typewhale.deepseek"
    private static let account = "api-key"

    static func load() -> String? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    static func hasAPIKey() -> Bool {
        load() != nil
    }

    static func save(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw DeepSeekAPIKeyStoreError.encodingFailed
        }

        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw DeepSeekAPIKeyStoreError.keychainStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw DeepSeekAPIKeyStoreError.keychainStatus(addStatus)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum DeepSeekAPIKeyStoreError: LocalizedError {
    case encodingFailed
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "DeepSeek API Key 编码失败"
        case .keychainStatus(let status):
            return "Keychain 写入失败：\(status)"
        }
    }
}
