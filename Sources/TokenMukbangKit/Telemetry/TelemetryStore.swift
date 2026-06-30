import Foundation

/// Persists ingested Claude Code telemetry to a local JSON file with rolling retention —
/// **app-only** (Application Support), never written into the widget-readable `SharedStore`
/// snapshot (ADR-0003 preserved; ADR-0023). Mirrors `HistoryStore`'s injectable-dir style.
public struct TelemetryStore: Sendable {
    public static let fileName = "telemetry.json"
    /// Keep 7 days (matches the longest usage window / history retention).
    public static let retention: TimeInterval = 7 * 24 * 60 * 60

    /// The stored shape: parallel metric + event arrays.
    public struct Contents: Codable, Sendable, Equatable {
        public var metrics: [TelemetryMetricSample]
        public var events: [TelemetryEventSample]
        public init(metrics: [TelemetryMetricSample] = [], events: [TelemetryEventSample] = []) {
            self.metrics = metrics; self.events = events
        }
    }

    private let directory: URL
    private let retention: TimeInterval

    public init(directory: URL? = nil, retention: TimeInterval = TelemetryStore.retention) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = support.appendingPathComponent("TokenMukbang", isDirectory: true)
        }
        self.retention = retention
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public func load() -> Contents {
        guard let data = try? Data(contentsOf: fileURL),
              let c = try? makeDecoder().decode(Contents.self, from: data) else { return Contents() }
        return c
    }

    /// Drop samples older than the retention window (keyed on each sample's timestamp).
    public func prune(_ c: Contents, now: Date) -> Contents {
        let cutoff = now.addingTimeInterval(-retention)
        return Contents(
            metrics: c.metrics.filter { $0.timestamp >= cutoff },
            events: c.events.filter { $0.timestamp >= cutoff }
        )
    }

    /// Append a freshly-ingested batch, prune, and persist. Returns the new retained set.
    @discardableResult
    public func append(metrics: [TelemetryMetricSample], events: [TelemetryEventSample], now: Date) -> Contents {
        var c = load()
        c.metrics.append(contentsOf: metrics)
        c.events.append(contentsOf: events)
        c = prune(c, now: now)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? makeEncoder().encode(c) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return c
    }
}
