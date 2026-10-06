import Foundation

@main
struct OnlineASRCredentialStoreCheck {
    static func main() throws {
        let backend = MemoryOnlineASRKeyValueBackend()
        let store = OnlineASRCredentialStore(backend: backend)

        precondition(!store.has(.doubaoAPIKey))
        precondition(!store.has(.mimoAPIKey))
        try store.save(" doubao-sentinel ", for: .doubaoAPIKey)
        try store.save("mimo-sentinel", for: .mimoAPIKey)
        precondition(store.load(.doubaoAPIKey) == "doubao-sentinel")
        precondition(store.load(.mimoAPIKey) == "mimo-sentinel")

        try store.save("doubao-replaced", for: .doubaoAPIKey)
        precondition(store.load(.doubaoAPIKey) == "doubao-replaced")
        precondition(store.load(.mimoAPIKey) == "mimo-sentinel")

        try store.save("  \n ", for: .doubaoAPIKey)
        precondition(!store.has(.doubaoAPIKey))
        store.delete(.mimoAPIKey)
        precondition(!store.has(.mimoAPIKey))
        print("OnlineASRCredentialStoreCheck passed")
    }
}

private final class MemoryOnlineASRKeyValueBackend: OnlineASRKeyValueBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func load(service: String, account: String) -> Data? {
        lock.withLock { values["\(service)|\(account)"] }
    }

    func save(_ data: Data, service: String, account: String) throws {
        lock.withLock { values["\(service)|\(account)"] = data }
    }

    func delete(service: String, account: String) {
        _ = lock.withLock { values.removeValue(forKey: "\(service)|\(account)") }
    }
}
