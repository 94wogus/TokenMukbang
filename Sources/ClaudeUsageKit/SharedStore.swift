import Foundation

/// Deliberate cached-payload bridge between the app and the WidgetKit extension.
///
/// The app runs the live pipeline (Keychain + network) and writes a
/// `UsageSnapshot` here; the widget — which must never touch Keychain or the
/// network from its sandbox — only ever *reads* the latest snapshot. The store
/// prefers the shared App Group container and falls back to Application Support
/// so it still works in unsigned/dev contexts without an App Group profile.
public struct SharedStore: Sendable {
    public static let appGroupID = "group.com.claudeusagewidget"
    public static let fileName = "usage-snapshot.json"

    private let appGroupID: String

    public init(appGroupID: String = SharedStore.appGroupID) {
        self.appGroupID = appGroupID
    }

    /// Directory the snapshot lives in: App Group container if available, else
    /// `~/Library/Application Support/ClaudeUsageWidget`.
    public func containerURL() -> URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("ClaudeUsageWidget", isDirectory: true)
    }

    private func fileURL() -> URL {
        containerURL().appendingPathComponent(Self.fileName)
    }

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Persist a snapshot for the widget to read. Best-effort; throws on I/O error.
    public func write(_ snapshot: UsageSnapshot) throws {
        let dir = containerURL()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder().encode(snapshot)
        try data.write(to: fileURL(), options: .atomic)
    }

    /// Load the latest snapshot, or nil if none has been written yet.
    public func read() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL()) else { return nil }
        return try? decoder().decode(UsageSnapshot.self, from: data)
    }
}
