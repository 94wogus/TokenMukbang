import Foundation

/// Decodes Claude Code's OTLP/HTTP **JSON** export (metrics + logs) into our domain
/// model. Pure + dependency-free → fully unit-tested; the App owns the socket (ADR-0023).
///
/// Two privacy/robustness invariants:
/// 1. **Content is never mapped.** Attribute keys in `contentKeys` (prompt/body/tool I/O/
///    refusal category) are skipped while parsing, so text never reaches the store even if
///    the user enables `OTEL_LOG_*` content flags — redaction at the collection point.
/// 2. **Lenient scalars.** OTLP/HTTP JSON encodes int64 as *strings* (`asInt:"1250"`,
///    `timeUnixNano:"...."`), so we accept both string- and number-encoded integers.
public enum OTLPDecoder {
    /// Text-bearing attribute keys to drop before they reach our model (ADR-0023).
    public static let contentKeys: Set<String> = [
        "prompt",        // user_prompt (OTEL_LOG_USER_PROMPTS)
        "body",          // api_request_body / api_response_body (OTEL_LOG_RAW_API_BODIES)
        "tool_input",    // tool I/O (OTEL_LOG_TOOL_CONTENT)
        "tool_output",
        "category",      // api_refusal policy category text
    ]

    public enum Kind: Sendable, Equatable { case metrics, logs }

    /// Route an OTLP/HTTP request path to the export kind it carries.
    public static func kind(forPath path: String) -> Kind? {
        if path.hasSuffix("/v1/metrics") { return .metrics }
        if path.hasSuffix("/v1/logs") { return .logs }
        return nil
    }

    // MARK: - Scalars

    /// Parse an OTLP `AnyValue` object into a `TelemetryValue` (scalars only).
    static func anyValue(_ v: [String: Any]) -> TelemetryValue? {
        if let s = v["stringValue"] as? String { return .string(s) }
        if let b = v["boolValue"] as? Bool { return .bool(b) }
        if let raw = v["intValue"], let i = asInt64(raw) { return .int(i) }
        if let raw = v["doubleValue"], let d = asDouble(raw) { return .double(d) }
        return nil
    }

    /// Accept an int64 encoded as a JSON number or a JSON string (OTLP/JSON does the latter).
    static func asInt64(_ raw: Any) -> Int64? {
        if let s = raw as? String { return Int64(s) }
        if let n = raw as? NSNumber { return n.int64Value }
        return nil
    }

    static func asDouble(_ raw: Any) -> Double? {
        if let s = raw as? String { return Double(s) }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    /// `timeUnixNano` (string or number) → `Date`. Missing/unparseable ⇒ epoch 0.
    static func date(fromUnixNano raw: Any?) -> Date {
        let ns = raw.flatMap(asDouble) ?? 0
        return Date(timeIntervalSince1970: ns / 1_000_000_000)
    }

    /// OTLP `attributes` array → dict, dropping content-bearing keys (ADR-0023).
    static func attributes(_ arr: [[String: Any]]?) -> [String: TelemetryValue] {
        var out: [String: TelemetryValue] = [:]
        for a in arr ?? [] {
            guard let key = a["key"] as? String, !contentKeys.contains(key),
                  let valObj = a["value"] as? [String: Any], let v = anyValue(valObj) else { continue }
            out[key] = v
        }
        return out
    }

    static func source(fromResource resource: [String: Any]?) -> TelemetrySource {
        let attrs = attributes(resource?["attributes"] as? [[String: Any]])
        func str(_ k: String) -> String? { attrs[k]?.stringValue }
        return TelemetrySource(
            serviceName: str("service.name"),
            sessionID: str("session.id"),
            userEmail: str("user.email"),
            userID: str("user.id"),
            organizationID: str("organization.id"),
            appVersion: str("service.version") ?? str("app.version"),
            osType: str("os.type"),
            terminalType: str("terminal.type")
        )
    }

    // MARK: - Metrics

    public static func decodeMetrics(_ data: Data) -> [TelemetryMetricSample] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resourceMetrics = root["resourceMetrics"] as? [[String: Any]] else { return [] }
        var out: [TelemetryMetricSample] = []
        for rm in resourceMetrics {
            let src = source(fromResource: rm["resource"] as? [String: Any])
            for sm in (rm["scopeMetrics"] as? [[String: Any]]) ?? [] {
                for metric in (sm["metrics"] as? [[String: Any]]) ?? [] {
                    guard let name = metric["name"] as? String else { continue }
                    // Claude Code emits sums (counters) and the cost gauge; both carry dataPoints.
                    let container = (metric["sum"] as? [String: Any]) ?? (metric["gauge"] as? [String: Any])
                    for dp in (container?["dataPoints"] as? [[String: Any]]) ?? [] {
                        guard let value = dataPointValue(dp) else { continue }
                        out.append(TelemetryMetricSample(
                            name: name, value: value, timestamp: date(fromUnixNano: dp["timeUnixNano"]),
                            attributes: attributes(dp["attributes"] as? [[String: Any]]), source: src))
                    }
                }
            }
        }
        return out
    }

    /// A NumberDataPoint's value — `asInt` (string-encoded) or `asDouble`.
    static func dataPointValue(_ dp: [String: Any]) -> TelemetryValue? {
        if let raw = dp["asInt"], let i = asInt64(raw) { return .int(i) }
        if let raw = dp["asDouble"], let d = asDouble(raw) { return .double(d) }
        return nil
    }

    // MARK: - Logs (events)

    public static func decodeLogs(_ data: Data) -> [TelemetryEventSample] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resourceLogs = root["resourceLogs"] as? [[String: Any]] else { return [] }
        var out: [TelemetryEventSample] = []
        for rl in resourceLogs {
            let src = source(fromResource: rl["resource"] as? [String: Any])
            for sl in (rl["scopeLogs"] as? [[String: Any]]) ?? [] {
                for record in (sl["logRecords"] as? [[String: Any]]) ?? [] {
                    let attrs = attributes(record["attributes"] as? [[String: Any]])
                    // Event name lives in the `event.name` attribute, with the log body as fallback.
                    let name = attrs["event.name"]?.stringValue
                        ?? (record["body"] as? [String: Any])?["stringValue"] as? String
                    guard let name else { continue }
                    out.append(TelemetryEventSample(
                        name: name, timestamp: date(fromUnixNano: record["timeUnixNano"]),
                        attributes: attrs, source: src))
                }
            }
        }
        return out
    }
}
