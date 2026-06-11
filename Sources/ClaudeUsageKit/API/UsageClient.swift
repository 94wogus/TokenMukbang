import Foundation

public enum UsageAPIError: Error, CustomStringConvertible {
    case http(status: Int)
    case transport(String)
    case decoding(String)

    public var description: String {
        switch self {
        case .http(let status):
            if status == 401 { return "Authorization failed (401) — the OAuth token may be expired." }
            return "Claude API returned HTTP \(status)."
        case .transport(let detail):
            return "Network error reaching Claude API: \(detail)"
        case .decoding(let detail):
            return "Could not decode Claude API response: \(detail)"
        }
    }
}

/// Fetches usage + profile from the Claude OAuth API. Abstracted so the CLI and
/// app can inject a fake (e.g. for previews or offline tests).
public protocol UsageFetching: Sendable {
    func fetchUsage(token: String) async throws -> Usage
    func fetchProfile(token: String) async throws -> Profile
}

/// Minimal transport seam so the live `URLSession` can be replaced in tests.
public protocol HTTPTransport: Sendable {
    func get(url: URL, headers: [String: String]) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func get(url: URL, headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            throw UsageAPIError.transport(error.localizedDescription)
        }
    }
}

public struct ClaudeUsageClient: UsageFetching {
    public static let baseURL = URL(string: "https://api.anthropic.com")!
    public static let betaHeader = "oauth-2025-04-20"

    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    private func headers(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": Self.betaHeader,
            "Content-Type": "application/json",
        ]
    }

    private func fetch<T: Decodable>(_ path: String, token: String, as type: T.Type) async throws -> T {
        let url = Self.baseURL.appendingPathComponent(path)
        let (data, status) = try await transport.get(url: url, headers: headers(token: token))
        guard (200..<300).contains(status) else { throw UsageAPIError.http(status: status) }
        do {
            return try ClaudeJSON.makeDecoder().decode(T.self, from: data)
        } catch {
            throw UsageAPIError.decoding(String(describing: error))
        }
    }

    public func fetchUsage(token: String) async throws -> Usage {
        try await fetch("api/oauth/usage", token: token, as: Usage.self)
    }

    public func fetchProfile(token: String) async throws -> Profile {
        try await fetch("api/oauth/profile", token: token, as: Profile.self)
    }
}
