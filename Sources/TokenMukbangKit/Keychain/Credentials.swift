import Foundation

/// The OAuth credential blob Claude Code stores under Keychain service
/// `Claude Code-credentials` (top-level key `claudeAiOauth`).
public struct OAuthCredentials: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    /// Epoch milliseconds.
    public let expiresAt: Double?
    public let scopes: [String]?
    public let subscriptionType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case scopes
        case subscriptionType
    }

    public var expiryDate: Date? {
        guard let ms = expiresAt else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }

    public func isExpired(asOf now: Date) -> Bool {
        guard let expiry = expiryDate else { return false }
        return expiry <= now
    }
}

private struct KeychainEnvelope: Codable {
    let claudeAiOauth: OAuthCredentials
}

/// Abstracts credential retrieval so the pipeline is testable without the real
/// Keychain (and so the GUI app can later swap in a `SecItem`-based provider).
public protocol CredentialProviding: Sendable {
    func loadCredentials() throws -> OAuthCredentials
}

public enum CredentialError: Error, Equatable, CustomStringConvertible {
    case notFound
    case malformed(String)

    public var description: String {
        switch self {
        case .notFound:
            return "Claude Code credentials not found in Keychain (service 'Claude Code-credentials'). Is Claude Code signed in?"
        case .malformed(let detail):
            return "Keychain credentials could not be parsed: \(detail)"
        }
    }
}

/// Default provider: shells out to `/usr/bin/security`, which reuses the calling
/// terminal's Keychain access and avoids a GUI prompt in headless contexts.
/// Read-only: it only ever reads the item, never mutates it.
public struct SecurityCLICredentialStore: CredentialProviding {
    public static let service = "Claude Code-credentials"

    private let runner: ProcessRunning

    public init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func loadCredentials() throws -> OAuthCredentials {
        let result = try runner.run(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", Self.service, "-w"]
        )
        guard result.exitCode == 0 else {
            throw CredentialError.notFound
        }
        let trimmed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !data.isEmpty else {
            throw CredentialError.notFound
        }
        do {
            return try JSONDecoder().decode(KeychainEnvelope.self, from: data).claudeAiOauth
        } catch {
            throw CredentialError.malformed(String(describing: error))
        }
    }
}
