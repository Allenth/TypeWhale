import Foundation
import Security

enum OnlineASRCredentialKind: String, CaseIterable, Sendable {
    case doubaoAPIKey
    case mimoAPIKey

    fileprivate var service: String {
        switch self {
        case .doubaoAPIKey:
            "com.waykingah.typewhale.pro.online-asr.doubao"
        case .mimoAPIKey:
            "com.waykingah.typewhale.pro.online-asr.mimo-v2.5"
        }
    }
}

protocol OnlineASRCredentialStoring: Sendable {
    func load(_ kind: OnlineASRCredentialKind) -> String?
    func has(_ kind: OnlineASRCredentialKind) -> Bool
    func save(_ value: String, for kind: OnlineASRCredentialKind) throws
    func delete(_ kind: OnlineASRCredentialKind)
}

protocol OnlineASRKeyValueBackend: Sendable {
    func load(service: String, account: String) -> Data?
    func save(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String)
}

struct OnlineASRCredentialStore: OnlineASRCredentialStoring {
    private static let account = "api-key"
    private let backend: any OnlineASRKeyValueBackend

    init(backend: any OnlineASRKeyValueBackend = KeychainOnlineASRKeyValueBackend()) {
        self.backend = backend
    }

    func load(_ kind: OnlineASRCredentialKind) -> String? {
        guard let data = backend.load(service: kind.service, account: Self.account),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func has(_ kind: OnlineASRCredentialKind) -> Bool {
        load(kind) != nil
    }

    func save(_ value: String, for kind: OnlineASRCredentialKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(kind)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw OnlineASRCredentialStoreError.encodingFailed
        }
        try backend.save(data, service: kind.service, account: Self.account)
    }

    func delete(_ kind: OnlineASRCredentialKind) {
        backend.delete(service: kind.service, account: Self.account)
    }
}

private struct KeychainOnlineASRKeyValueBackend: OnlineASRKeyValueBackend {
    func load(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func save(_ data: Data, service: String, account: String) throws {
        var query = baseQuery(service: service, account: account)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw OnlineASRCredentialStoreError.keychainStatus(updateStatus)
        }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OnlineASRCredentialStoreError.keychainStatus(addStatus)
        }
    }

    func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum OnlineASRCredentialStoreError: LocalizedError {
    case encodingFailed
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "在线 ASR 凭证编码失败"
        case .keychainStatus(let status):
            "Keychain 写入失败：\(status)"
        }
    }
}
