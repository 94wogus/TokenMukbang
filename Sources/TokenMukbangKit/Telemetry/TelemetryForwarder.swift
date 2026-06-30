import Foundation

/// POST seam for forwarding (ADR-0006 style) so the live `URLSession` can be faked in tests.
public protocol OTLPForwarding: Sendable {
    /// POST `body` to `url` with `headers`; returns the HTTP status (0 on transport failure).
    func post(url: URL, headers: [String: String], body: Data) async -> Int
}

public struct URLSessionForwarding: OTLPForwarding {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func post(url: URL, headers: [String: String], body: Data) async -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return 0   // best-effort: forwarding never throws into the receive path
        }
    }
}

/// Forwards content-stripped telemetry to a company OTLP endpoint (ADR-0024 Slice 2).
/// Re-encodes from our model via `OTLPEncoder` (never the raw received bytes), so content can't
/// leak. Best-effort: failures are swallowed — egress must never break local ingestion.
public struct TelemetryForwarder: Sendable {
    private let base: URL
    private let token: String
    private let transport: OTLPForwarding

    /// `endpoint` is the company OTLP base (e.g. `https://host/api/otel`); we append the signal path.
    /// Returns nil if the endpoint isn't a valid URL.
    public init?(endpoint: String, token: String, transport: OTLPForwarding = URLSessionForwarding()) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
        self.base = url
        self.token = token
        self.transport = transport
    }

    private func headers() -> [String: String] {
        var h = ["Content-Type": "application/json"]
        if !token.isEmpty { h["Authorization"] = "Bearer \(token)" }
        return h
    }

    /// `base` + `/v1/metrics` etc., tolerant of a trailing slash on the configured endpoint.
    func url(forSignal signal: String) -> URL {
        base.appendingPathComponent(signal)
    }

    @discardableResult
    public func forward(metrics: [TelemetryMetricSample]) async -> Int {
        guard !metrics.isEmpty else { return 0 }
        return await transport.post(url: url(forSignal: "v1/metrics"),
                                    headers: headers(), body: OTLPEncoder.encodeMetrics(metrics))
    }

    @discardableResult
    public func forward(events: [TelemetryEventSample]) async -> Int {
        guard !events.isEmpty else { return 0 }
        return await transport.post(url: url(forSignal: "v1/logs"),
                                    headers: headers(), body: OTLPEncoder.encodeLogs(events))
    }
}
