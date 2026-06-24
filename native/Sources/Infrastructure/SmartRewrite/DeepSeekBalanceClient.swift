import Foundation

struct DeepSeekBalanceSummary: Equatable {
    let currency: String
    let currentBalance: Double
    let grantedBalance: Double
    let toppedUpBalance: Double
    let isAvailable: Bool

    static let empty = DeepSeekBalanceSummary(
        currency: "CNY",
        currentBalance: 0,
        grantedBalance: 0,
        toppedUpBalance: 0,
        isAvailable: false
    )
}

final class DeepSeekBalanceClient {
    private let endpoint = URL(string: "https://api.deepseek.com/user/balance")!
    private let apiKeyProvider: () -> String?
    private let session: URLSession

    init(
        apiKeyProvider: @escaping () -> String? = { DeepSeekAPIKeyStore.load() },
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func fetch() async throws -> DeepSeekBalanceSummary {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw DeepSeekBalanceError.missingAPIKey
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekBalanceError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw DeepSeekBalanceError.httpStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        let preferred = decoded.balanceInfos.first { $0.currency.uppercased() == "CNY" }
            ?? decoded.balanceInfos.first
        guard let preferred else {
            return DeepSeekBalanceSummary.empty
        }
        return DeepSeekBalanceSummary(
            currency: preferred.currency,
            currentBalance: Double(preferred.totalBalance) ?? 0,
            grantedBalance: Double(preferred.grantedBalance) ?? 0,
            toppedUpBalance: Double(preferred.toppedUpBalance) ?? 0,
            isAvailable: decoded.isAvailable
        )
    }
}

enum DeepSeekBalanceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先设置 DeepSeek API Key"
        case .invalidResponse:
            return "DeepSeek 余额接口返回无效响应"
        case .httpStatus(let status):
            return "DeepSeek 余额接口请求失败：HTTP \(status)"
        }
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}
