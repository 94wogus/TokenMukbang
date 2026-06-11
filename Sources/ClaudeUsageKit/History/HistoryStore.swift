import Foundation

/// One historical usage sample: per-window utilization at a moment in time.
/// Compact on purpose — history is appended every poll and kept for 7 days.
public struct HistorySample: Codable, Sendable, Equatable {
    public let capturedAt: Date
    /// windowKind (UsageWindowKind.rawValue) → utilization 0...100.
    public let utilizations: [String: Double]

    public init(capturedAt: Date, utilizations: [String: Double]) {
        self.capturedAt = capturedAt
        self.utilizations = utilizations
    }

    /// Build a sample from a live snapshot's windows.
    public init(snapshot: UsageSnapshot) {
        self.capturedAt = snapshot.capturedAt
        self.utilizations = Dictionary(
            uniqueKeysWithValues: snapshot.windows.map { ($0.kind, $0.utilization) }
        )
    }
}

/// Appends `HistorySample`s to a local JSON file with a rolling retention window,
/// so the dashboard can draw 7-day sparklines/graphs and a history browser.
/// The directory is injectable for tests (ADR-0006 seam style).
public struct HistoryStore: Sendable {
    public static let fileName = "history.json"
    /// Keep 7 days of history (matches the longest usage window).
    public static let retention: TimeInterval = 7 * 24 * 60 * 60

    private let directory: URL
    private let retention: TimeInterval

    public init(directory: URL? = nil, retention: TimeInterval = HistoryStore.retention) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = support.appendingPathComponent("ClaudeUsageWidget", isDirectory: true)
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

    /// All retained samples, oldest first. Empty if nothing stored yet.
    public func load() -> [HistorySample] {
        guard let data = try? Data(contentsOf: fileURL),
              let samples = try? makeDecoder().decode([HistorySample].self, from: data)
        else { return [] }
        return samples.sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Drop samples older than the retention window.
    public func prune(_ samples: [HistorySample], now: Date) -> [HistorySample] {
        let cutoff = now.addingTimeInterval(-retention)
        return samples.filter { $0.capturedAt >= cutoff }
    }

    /// Append a sample, prune, and persist. Returns the new retained set.
    @discardableResult
    public func append(_ sample: HistorySample, now: Date) -> [HistorySample] {
        var samples = load()
        samples.append(sample)
        samples = prune(samples, now: now).sorted { $0.capturedAt < $1.capturedAt }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? makeEncoder().encode(samples) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return samples
    }

    /// Convenience: record a live snapshot (skips error-only snapshots with no windows).
    @discardableResult
    public func record(_ snapshot: UsageSnapshot) -> [HistorySample] {
        guard !snapshot.windows.isEmpty else { return load() }
        return append(HistorySample(snapshot: snapshot), now: snapshot.capturedAt)
    }
}
