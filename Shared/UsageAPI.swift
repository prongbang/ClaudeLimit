import Foundation

enum UsageAPIError: LocalizedError {
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(401): return "Unauthorized (401) — run claude to refresh the token"
        case .http(429): return "Rate limited (429) — try again in a moment"
        case .http(let code): return "HTTP \(code)"
        case .badResponse: return "Invalid response"
        }
    }
}

enum UsageAPI {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Same data source as Claude Code's `/usage` command.
    /// Poll at >= 180s intervals to stay under the rate limit.
    static func fetch() async throws -> UsageSnapshot {
        let token = try await CredentialsProvider.accessToken()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // Required — without this UA the endpoint 429s aggressively.
        request.setValue("claude-code/2.0.14", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageAPIError.badResponse }
        guard http.statusCode == 200 else { throw UsageAPIError.http(http.statusCode) }

        var snapshot = try UsageDateParsing.makeAPIDecoder().decode(UsageSnapshot.self, from: data)
        snapshot.fetchedAt = Date()
        return snapshot
    }
}
