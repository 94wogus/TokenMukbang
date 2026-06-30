import Foundation

/// Re-encodes our domain model back into OTLP/HTTP **JSON** for forwarding to a company
/// endpoint (ADR-0024 Slice 2). The forwarder always re-encodes *from the content-stripped
/// model* — it never passes the raw received bytes through — so text the user may have enabled
/// via `OTEL_LOG_*` can never leak downstream. The inverse of `OTLPDecoder`.
public enum OTLPEncoder {
    /// Scope name on forwarded data, so the company side can tell it came via TokenMukbang.
    public static let scopeName = "com.tokenmukbang.forward"

    static func anyValueJSON(_ v: TelemetryValue) -> [String: Any] {
        switch v {
        case .string(let s): return ["stringValue": s]
        case .int(let i): return ["intValue": String(i)]   // OTLP/JSON encodes int64 as a string
        case .double(let d): return ["doubleValue": d]
        case .bool(let b): return ["boolValue": b]
        }
    }

    static func attrsJSON(_ attrs: [String: TelemetryValue]) -> [[String: Any]] {
        // Sort for deterministic output (stable tests / diffs).
        attrs.sorted { $0.key < $1.key }.map { ["key": $0.key, "value": anyValueJSON($0.value)] }
    }

    static func resourceJSON(_ s: TelemetrySource) -> [String: Any] {
        var attrs: [[String: Any]] = []
        func add(_ key: String, _ value: String?) {
            if let value { attrs.append(["key": key, "value": ["stringValue": value]]) }
        }
        add("service.name", s.serviceName)
        add("service.version", s.appVersion)
        add("session.id", s.sessionID)
        add("user.email", s.userEmail)
        add("user.id", s.userID)
        add("organization.id", s.organizationID)
        add("os.type", s.osType)
        add("terminal.type", s.terminalType)
        return ["attributes": attrs]
    }

    static func nanoString(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded()))
    }

    static func valueJSON(_ v: TelemetryValue) -> [String: Any] {
        switch v {
        case .int(let i): return ["asInt": String(i)]
        case .double(let d): return ["asDouble": d]
        case .bool(let b): return ["asInt": b ? "1" : "0"]
        case .string: return ["asInt": "0"]   // shouldn't happen for a metric value
        }
    }

    public static func encodeMetrics(_ samples: [TelemetryMetricSample]) -> Data {
        let resourceMetrics = Dictionary(grouping: samples, by: { $0.source }).map { source, group -> [String: Any] in
            let metrics = group.map { s -> [String: Any] in
                let dp: [String: Any] = valueJSON(s.value)
                    .merging(["timeUnixNano": nanoString(s.timestamp), "attributes": attrsJSON(s.attributes)]) { a, _ in a }
                return ["name": s.name, "sum": ["dataPoints": [dp], "isMonotonic": true]]
            }
            return ["resource": resourceJSON(source),
                    "scopeMetrics": [["scope": ["name": scopeName], "metrics": metrics]]]
        }
        return json(["resourceMetrics": resourceMetrics])
    }

    public static func encodeLogs(_ events: [TelemetryEventSample]) -> Data {
        let resourceLogs = Dictionary(grouping: events, by: { $0.source }).map { source, group -> [String: Any] in
            let records = group.map { e -> [String: Any] in
                ["timeUnixNano": nanoString(e.timestamp),
                 "body": ["stringValue": e.name],
                 "attributes": attrsJSON(e.attributes)]
            }
            return ["resource": resourceJSON(source),
                    "scopeLogs": [["scope": ["name": scopeName], "logRecords": records]]]
        }
        return json(["resourceLogs": resourceLogs])
    }

    private static func json(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
