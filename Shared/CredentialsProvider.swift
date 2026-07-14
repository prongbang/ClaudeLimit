import Foundation
import Security

enum CredentialsError: LocalizedError {
    case notFound
    case expired(Date)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude Code credentials not found — run claude in Terminal first"
        case .expired(let date):
            return "Token expired at \(date.formatted()) — run claude to refresh"
        }
    }
}

/// Reads the Claude Code OAuth access token.
/// Order: env var → macOS Keychain → ~/.claude/.credentials.json
enum CredentialsProvider {

    static func accessToken() throws -> String {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !env.isEmpty {
            return env
        }
        if let data = keychainCredentials() ?? fileCredentials() {
            return try parse(data)
        }
        throw CredentialsError.notFound
    }

    /// Subscription plan from the credentials payload (e.g. "max", "pro"), if present.
    static func subscriptionType() -> String? {
        guard let data = keychainCredentials() ?? fileCredentials() else { return nil }
        struct Credentials: Decodable {
            struct OAuth: Decodable { let subscriptionType: String? }
            let claudeAiOauth: OAuth
        }
        return (try? JSONDecoder().decode(Credentials.self, from: data))?
            .claudeAiOauth.subscriptionType
    }

    // MARK: - Sources

    private static func keychainCredentials() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func fileCredentials() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }

    // MARK: - Parsing

    private static func parse(_ data: Data) throws -> String {
        struct Credentials: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: Double? // epoch milliseconds
            }
            let claudeAiOauth: OAuth
        }
        guard let creds = try? JSONDecoder().decode(Credentials.self, from: data) else {
            throw CredentialsError.notFound
        }
        if let ms = creds.claudeAiOauth.expiresAt {
            let expiry = Date(timeIntervalSince1970: ms / 1000)
            // 60s buffer
            if expiry.timeIntervalSinceNow < 60 {
                throw CredentialsError.expired(expiry)
            }
        }
        return creds.claudeAiOauth.accessToken
    }
}
