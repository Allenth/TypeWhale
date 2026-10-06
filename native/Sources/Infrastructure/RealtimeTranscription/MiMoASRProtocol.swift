import Foundation

enum MiMoASRLanguage: String, Sendable, CaseIterable {
    case auto
    case zh
    case en
}

enum MiMoASRProtocolError: Error, Sendable, Equatable, CustomStringConvertible {
    case audioTooLarge
    case invalidRequest
    case invalidUTF8
    case invalidJSON
    case streamBufferOverflow

    var description: String {
        switch self {
        case .audioTooLarge: "MiMo audio request exceeds the local safety limit"
        case .invalidRequest: "MiMo request could not be encoded"
        case .invalidUTF8: "MiMo stream contains invalid UTF-8"
        case .invalidJSON: "MiMo stream contains invalid JSON"
        case .streamBufferOverflow: "MiMo stream buffer reached its safety limit"
        }
    }
}

struct MiMoASRRequestBuilder: Sendable {
    static let endpoint = URL(string: "https://api.xiaomimimo.com/v1/chat/completions")!
    static let model = "mimo-v2.5-asr"
    static let maximumRequestBytes = 9_000_000

    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func makeRequest(wavData: Data, language: MiMoASRLanguage) throws -> URLRequest {
        let dataURL = "data:audio/wav;base64," + wavData.base64EncodedString()
        guard dataURL.utf8.count <= Self.maximumRequestBytes else {
            throw MiMoASRProtocolError.audioTooLarge
        }

        let body: [String: Any] = [
            "model": Self.model,
            "messages": [[
                "role": "user",
                "content": [[
                    "type": "input_audio",
                    "input_audio": ["data": dataURL],
                ]],
            ]],
            "asr_options": ["language": language.rawValue],
            "stream": true,
        ]
        guard JSONSerialization.isValidJSONObject(body) else {
            throw MiMoASRProtocolError.invalidRequest
        }
        let encoded: Data
        do {
            encoded = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        } catch {
            throw MiMoASRProtocolError.invalidRequest
        }
        guard encoded.count <= Self.maximumRequestBytes else {
            throw MiMoASRProtocolError.audioTooLarge
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = encoded
        return request
    }
}

enum MiMoASRDelta: Sendable, Equatable {
    case text(String)
    case completed
}

struct MiMoSSEParser: Sendable {
    private var buffer = Data()
    private var terminal = false
    private let maximumBufferedBytes: Int

    init(maximumBufferedBytes: Int = 1_000_000) {
        self.maximumBufferedBytes = max(1, maximumBufferedBytes)
    }

    mutating func append<D: DataProtocol>(_ bytes: D) throws -> [MiMoASRDelta] where D.Element == UInt8 {
        guard !terminal else { return [] }
        buffer.append(contentsOf: bytes)
        var output: [MiMoASRDelta] = []

        while let boundary = eventBoundary(in: buffer) {
            guard boundary.lowerBound <= maximumBufferedBytes else {
                buffer.removeAll(keepingCapacity: false)
                throw MiMoASRProtocolError.streamBufferOverflow
            }
            let eventData = buffer.subdata(in: 0..<boundary.lowerBound)
            buffer.removeSubrange(0..<boundary.upperBound)
            let events = try parseEvent(eventData)
            output.append(contentsOf: events)
            if terminal {
                buffer.removeAll(keepingCapacity: false)
                return output
            }
        }

        guard buffer.count <= maximumBufferedBytes else {
            buffer.removeAll(keepingCapacity: false)
            throw MiMoASRProtocolError.streamBufferOverflow
        }
        return output
    }

    private func eventBoundary(in data: Data) -> Range<Int>? {
        guard data.count >= 2 else { return nil }
        var index = 0
        while index < data.count - 1 {
            if data[index] == 0x0A, data[index + 1] == 0x0A {
                return index..<(index + 2)
            }
            if data[index] == 0x0D {
                if data[index + 1] == 0x0D {
                    return index..<(index + 2)
                }
                if index + 3 < data.count,
                   data[index + 1] == 0x0A,
                   data[index + 2] == 0x0D,
                   data[index + 3] == 0x0A {
                    return index..<(index + 4)
                }
            }
            index += 1
        }
        return nil
    }

    private mutating func parseEvent(_ data: Data) throws -> [MiMoASRDelta] {
        guard !data.isEmpty else { return [] }
        guard var text = String(data: data, encoding: .utf8) else {
            throw MiMoASRProtocolError.invalidUTF8
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        var dataLines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            if line == "data" {
                dataLines.append("")
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                dataLines.append(String(value))
            }
        }
        guard !dataLines.isEmpty else { return [] }

        let payload = dataLines.joined(separator: "\n")
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            terminal = true
            return [.completed]
        }
        guard let jsonData = payload.data(using: .utf8) else {
            throw MiMoASRProtocolError.invalidUTF8
        }
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw MiMoASRProtocolError.invalidJSON
            }
            object = parsed
        } catch let error as MiMoASRProtocolError {
            throw error
        } catch {
            throw MiMoASRProtocolError.invalidJSON
        }

        guard let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first,
              let delta = choice["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else {
            return []
        }
        return [.text(content)]
    }
}
