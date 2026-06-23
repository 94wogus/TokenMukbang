import Foundation

/// A parse cache for transcript token events. `JSONLParser.events(...)` is the raw parser; this
/// avoids re-reading and re-parsing **every** `~/.claude/projects/*.jsonl` (a heavy user: >1GB /
/// ~2.2k files, ~25s) on each refresh by keying parsed events to each file's `(size, mtime)`.
///
/// Two modes (ADR-0021 — A/B refresh):
///  • **`load`** (A, authoritative): disk-cache-backed full rebuild — reuses the persisted cache for
///    unchanged files, re-parses changed ones, and **rewrites the cache**. Used on launch and the
///    manual ↻ refresh.
///  • **`update`** (B, incremental): from a previous in-memory `Snapshot`, re-parses only files whose
///    `(size, mtime)` changed and reuses the rest **from memory** — no disk read/write. Used on the
///    5-min poll so the Value/History numbers stay live without paying the full-cache I/O each tick
///    (which grows with history). Persistence is left to the next `load`; `load`'s mtime check
///    self-heals any drift at launch.
///
/// Pure Foundation (ADR-0001); the cache directory is injectable for tests. The cache is a derived,
/// disposable artifact — deleting it just forces a one-time full re-parse.
public enum EventCache {
    public static let fileName = "event-cache.json"

    /// One transcript file's parse result, validated by its filesystem identity.
    struct Entry: Codable, Sendable {
        let size: Int
        let mtime: Double          // modification time as a unix interval
        let events: [TokenEvent]
    }

    private struct Cache: Codable { var files: [String: Entry] }

    /// An in-memory parse result: per-file entries (for incremental diffing) + the flattened,
    /// timestamp-sorted events the app consumes. Carried across refreshes so `update` can diff.
    public struct Snapshot: Sendable {
        let files: [String: Entry]
        public let events: [TokenEvent]
        init(files: [String: Entry]) {
            self.files = files
            self.events = files.values.flatMap(\.events).sorted { $0.timestamp < $1.timestamp }
        }
    }

    /// **(A) Full, authoritative load** — disk-cache-backed. Reuses the persisted cache for files
    /// whose `(size, mtime)` is unchanged, re-parses the rest, and rewrites the cache.
    public static func load(claudeHome: String? = nil, cacheDirectory: URL? = nil) -> Snapshot {
        let cacheURL = resolveCacheURL(cacheDirectory)
        let old = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }?.files ?? [:]

        let (fresh, reparsed) = rebuild(reusing: old, claudeHome: claudeHome)

        if reparsed > 0 || fresh.count != old.count {
            let fm = FileManager.default
            try? fm.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(Cache(files: fresh)) {
                try? data.write(to: cacheURL, options: .atomic)
            }
        }
        return Snapshot(files: fresh)
    }

    /// **(B) Incremental update** — from a previous in-memory snapshot, re-parse only changed/new
    /// files (reuse the rest from memory) and drop deleted ones. No disk read/write. Cheap and
    /// independent of total history size — what makes per-poll refresh affordable.
    public static func update(previous: Snapshot, claudeHome: String? = nil) -> Snapshot {
        let (fresh, _) = rebuild(reusing: previous.files, claudeHome: claudeHome)
        return Snapshot(files: fresh)
    }

    /// Backward-compatible convenience (usage-cli / tests): full load → flat events.
    public static func allEvents(claudeHome: String? = nil, cacheDirectory: URL? = nil) -> [TokenEvent] {
        load(claudeHome: claudeHome, cacheDirectory: cacheDirectory).events
    }

    /// Walk every `.jsonl` under `projects/`; reuse `reusing[path]` when `(size, mtime)` matches,
    /// else re-parse. Returns the rebuilt per-file map + how many files were re-parsed.
    private static func rebuild(reusing: [String: Entry], claudeHome: String?) -> (files: [String: Entry], reparsed: Int) {
        let home = claudeHome ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let projects = (home as NSString).appendingPathComponent("projects")
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projects) else { return ([:], 0) }

        var fresh: [String: Entry] = [:]
        var reparsed = 0
        for dir in dirs {
            let dirPath = (projects as NSString).appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = (dirPath as NSString).appendingPathComponent(file)
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
                let size = (attrs[.size] as? Int) ?? -1
                let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1

                if let hit = reusing[path], hit.size == size, hit.mtime == mtime {
                    fresh[path] = hit
                } else if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                    fresh[path] = Entry(size: size, mtime: mtime, events: JSONLParser.events(fromTranscript: contents))
                    reparsed += 1
                }
            }
        }
        return (fresh, reparsed)
    }

    private static func resolveCacheURL(_ dir: URL?) -> URL {
        let base: URL
        if let dir { base = dir } else {
            base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("TokenMukbang", isDirectory: true)
        }
        return base.appendingPathComponent(fileName)
    }
}
