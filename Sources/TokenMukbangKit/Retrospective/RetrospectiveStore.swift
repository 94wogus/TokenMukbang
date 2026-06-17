import Foundation

/// Persists generated `RetrospectiveSummary`s to a local JSON file, keyed by UTC day.
///
/// **App-only on purpose** (ADR-0003 + ADR-0020): retrospectives carry content-derived
/// text (`topics`), so they live in Application Support — the same place as `HistoryStore`
/// (ADR-0011) — and are **never** written into the App Group `SharedStore` snapshot the
/// sandboxed widget reads. The directory is injectable for tests (ADR-0006 seam style).
///
/// Day-keying doubles as the on-demand cache: a second "generate" on the same day reuses
/// the stored result instead of spending tokens again (먹방 paradox, ADR-0020).
public struct RetrospectiveStore: Sendable {
    public static let fileName = "retrospective.json"

    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = support.appendingPathComponent("TokenMukbang", isDirectory: true)
        }
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// UTC `yyyy-MM-dd` key for a period — derived from its start date.
    public static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// All stored retrospectives, keyed by UTC day. Empty if nothing stored yet.
    public func load() -> [String: RetrospectiveSummary] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? makeDecoder().decode([String: RetrospectiveSummary].self, from: data)
        else { return [:] }
        return map
    }

    /// The retrospective stored for `dayKey`, if any (on-demand cache hit).
    public func summary(forDayKey dayKey: String) -> RetrospectiveSummary? {
        load()[dayKey]
    }

    /// Convenience: cached retrospective whose period covers `date`'s UTC day.
    public func summary(for date: Date) -> RetrospectiveSummary? {
        summary(forDayKey: Self.dayKey(for: date))
    }

    /// Store `summary` under the key derived from its `periodStart`, persisting the map.
    @discardableResult
    public func save(_ summary: RetrospectiveSummary) -> [String: RetrospectiveSummary] {
        var map = load()
        map[Self.dayKey(for: summary.periodStart)] = summary
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? makeEncoder().encode(map) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return map
    }
}
