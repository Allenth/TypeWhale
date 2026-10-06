import Foundation

protocol MiMoHTTPStreaming: Sendable {
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error>
    func cancel() async
}

protocol MiMoASRRequestBuilding: Sendable {
    func makeRequest(wavData: Data, language: MiMoASRLanguage) throws -> URLRequest
}

extension MiMoASRRequestBuilder: MiMoASRRequestBuilding {}

enum MiMoHTTPError: Error, Sendable, Equatable {
    case invalidResponse
    case status(Int)
}

actor MiMoHTTPTransport: MiMoHTTPStreaming {
    private let session: URLSession
    private var producer: Task<Void, Never>?

    init(configuration: URLSessionConfiguration = .ephemeral) {
        session = URLSession(configuration: configuration)
    }

    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        await cancel()
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        producer = Task { [session] in
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw MiMoHTTPError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw MiMoHTTPError.status(http.statusCode)
                }

                var chunk = Data()
                chunk.reserveCapacity(4_096)
                for try await byte in bytes {
                    try Task.checkCancellation()
                    chunk.append(byte)
                    if chunk.count >= 4_096 {
                        pair.continuation.yield(chunk)
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                if !chunk.isEmpty { pair.continuation.yield(chunk) }
                pair.continuation.finish()
            } catch {
                pair.continuation.finish(throwing: error)
            }
        }
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.cancel() }
        }
        return pair.stream
    }

    func cancel() async {
        producer?.cancel()
        producer = nil
    }
}
