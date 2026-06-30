import Foundation

/// A single OTLP attribute value, narrowed to the scalar kinds Claude Code emits
/// (`arrayValue`/`kvlistValue` are ignored — Claude Code's telemetry doesn't use them
/// for the fields we keep). Codable so the app-only `TelemetryStore` can round-trip it.
public enum TelemetryValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    /// Convenience readers for downstream aggregation.
    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }
    public var intValue: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        default: return nil
        }
    }
}

/// The resource (common) attributes Claude Code attaches to every metric/event —
/// "who/where", never "what". No content fields (ADR-0023).
public struct TelemetrySource: Codable, Sendable, Equatable, Hashable {
    public var serviceName: String?      // service.name = "claude-code"
    public var sessionID: String?        // session.id
    public var userEmail: String?        // user.email
    public var userID: String?           // user.id
    public var organizationID: String?   // organization.id
    public var appVersion: String?       // service.version / app.version
    public var osType: String?           // os.type
    public var terminalType: String?     // terminal.type

    public init(serviceName: String? = nil, sessionID: String? = nil, userEmail: String? = nil,
                userID: String? = nil, organizationID: String? = nil, appVersion: String? = nil,
                osType: String? = nil, terminalType: String? = nil) {
        self.serviceName = serviceName; self.sessionID = sessionID; self.userEmail = userEmail
        self.userID = userID; self.organizationID = organizationID; self.appVersion = appVersion
        self.osType = osType; self.terminalType = terminalType
    }
}

/// One Claude Code metric data point (e.g. `claude_code.token.usage` with `type=input`).
public struct TelemetryMetricSample: Codable, Sendable, Equatable {
    public let name: String                       // e.g. "claude_code.token.usage"
    public let value: TelemetryValue              // .int (counts/tokens) or .double (cost/seconds)
    public let timestamp: Date
    public let attributes: [String: TelemetryValue]  // low-cardinality: model, type, decision, …
    public let source: TelemetrySource

    public init(name: String, value: TelemetryValue, timestamp: Date,
                attributes: [String: TelemetryValue], source: TelemetrySource) {
        self.name = name; self.value = value; self.timestamp = timestamp
        self.attributes = attributes; self.source = source
    }
}

/// One Claude Code log event (e.g. `claude_code.api_request`). Content attributes
/// (`prompt`, `body`, `tool_input`, `tool_output`, `category`) are dropped at decode
/// time, so only metadata reaches this model (ADR-0023).
public struct TelemetryEventSample: Codable, Sendable, Equatable {
    public let name: String                       // event.name e.g. "claude_code.api_request"
    public let timestamp: Date
    public let attributes: [String: TelemetryValue]
    public let source: TelemetrySource

    public init(name: String, timestamp: Date, attributes: [String: TelemetryValue], source: TelemetrySource) {
        self.name = name; self.timestamp = timestamp; self.attributes = attributes; self.source = source
    }
}
