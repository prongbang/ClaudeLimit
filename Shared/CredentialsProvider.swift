import Foundation
import Security

enum CredentialsError: LocalizedError {
    case notFound
    case expired(Date)
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude Code credentials not found — run claude in Terminal first"
        case .expired(let date):
            return "Token expired at \(date.formatted()) — run claude to refresh"
        case .refreshFailed(let reason):
            return "Token auto-refresh failed (\(reason)) — run claude to sign in again"
        }
    }
}

/// Reads the Claude Code OAuth access token.
/// Order: env var → macOS Keychain → ~/.claude/.credentials.json
/// An expired token is refreshed automatically using the stored refresh token
/// (same OAuth client as Claude Code) and the rotated credentials are written
/// back to the source so Claude Code itself keeps working.
enum CredentialsProvider {

    private static let service = "Claude Code-credentials"
    private static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    /// Claude Code's public OAuth client id.
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private enum Source: Equatable { case keychain(account: String), file }

    static func accessToken() throws -> String {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !env.isEmpty {
            return env
        }
        guard let (data, _) = rawCredentials(),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw CredentialsError.notFound
        }

        let expiry = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        // 60s buffer
        guard let expiry, expiry.timeIntervalSinceNow < 60 else { return token }
        throw CredentialsError.expired(expiry)
    }

    /// Exchanges the stored refresh token for new credentials and persists
    /// them back to the source. User-initiated only — it writes to the
    /// Keychain, which may trigger an authorization prompt.
    static func refreshExpiredToken() async throws {
        guard let (data, source) = rawCredentials(),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else {
            throw CredentialsError.notFound
        }
        guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw CredentialsError.refreshFailed("no refresh token")
        }
        let fresh = try await refresh(with: refreshToken)

        oauth["accessToken"] = fresh.accessToken
        oauth["expiresAt"] = Int((Date().timeIntervalSince1970 + Double(fresh.expiresIn)) * 1000)
        // The refresh token may rotate — persisting it is what keeps
        // Claude Code's own copy valid.
        if let rotated = fresh.refreshToken { oauth["refreshToken"] = rotated }
        root["claudeAiOauth"] = oauth
        if let updated = try? JSONSerialization.data(withJSONObject: root) {
            persist(updated, to: source)
        }
    }

    /// Subscription plan from the credentials payload (e.g. "max", "pro"), if present.
    static func subscriptionType() -> String? {
        guard let (data, _) = rawCredentials(),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["subscriptionType"] as? String
    }

    // MARK: - Refresh

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private static func refresh(with refreshToken: String) async throws -> RefreshResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CredentialsError.refreshFailed("no response")
        }
        guard http.statusCode == 200 else {
            throw CredentialsError.refreshFailed("HTTP \(http.statusCode)")
        }
        guard let parsed = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw CredentialsError.refreshFailed("unexpected response")
        }
        return parsed
    }

    // MARK: - Sources

    private static func rawCredentials() -> (Data, Source)? {
        if let (data, account) = keychainCredentials() {
            return (data, .keychain(account: account))
        }
        if let data = try? Data(contentsOf: credentialsFileURL) { return (data, .file) }
        return nil
    }

    private static var credentialsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private static func keychainCredentials() -> (Data, account: String)? {
        // Read through /usr/bin/security — the same trusted tool Claude Code
        // itself uses — so this app never triggers a keychain authorization
        // prompt, even when the ad-hoc signature changes between builds.
        guard let value = runSecurity(["find-generic-password", "-s", service, "-w"]),
              !value.isEmpty else { return nil }
        let attrs = runSecurity(["find-generic-password", "-s", service]) ?? ""
        let account = attrs
            .components(separatedBy: "\"acct\"<blob>=\"").dropFirst().first?
            .components(separatedBy: "\"").first ?? NSUserName()
        return (Data(value.utf8), account)
    }

    private static func runSecurity(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func persist(_ data: Data, to source: Source) {
        switch source {
        case .keychain(let account):
            // Write through /usr/bin/security so the item keeps its default
            // ACL. SecItemUpdate from this app would re-scope the item to
            // this binary only, locking out Claude Code and the security
            // tool and causing endless keychain password prompts.
            guard let json = String(data: data, encoding: .utf8),
                  !json.contains("'") else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["-i"]
            let stdin = Pipe()
            process.standardInput = stdin
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            let command = "add-generic-password -U -s '\(service)' -a '\(account)' -w '\(json)'\n"
            stdin.fileHandleForWriting.write(Data(command.utf8))
            stdin.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        case .file:
            try? data.write(to: credentialsFileURL, options: .atomic)
        }
    }
}
