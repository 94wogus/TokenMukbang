import Foundation

/// A persistent parse cache for transcript token events. `JSONLParser.allEvents()` re-reads and
/// re-parses **every** `~/.claude/projects/*.jsonl` on each launch — for a heavy user that's >1GB
/// and ~25s of CPU before History/Retro/Value have any data. This caches parsed `TokenEvent`s
/// keyed by each file's `(size, mtime)`: unchanged files (almost all of them — completed sessions
/// never change) are served from the cache, and only new/appended files are re-parsed.
///
/// Pure Foundation (ADR-0001); the cache directory is injectable for tests. The cache is a
/// derived, disposable artifact — deleting it just forces a one-time full re-parse.
public enum EventCache {
    public static let fileName = "event-cache.json"

    /// One transcript file's parse result, validated by its filesystem identity.
    struct Entry: Codable {
        let size: Int
        let mtime: Double          // modification time as a unix interval
        let events: [TokenEvent]
    }

    private struct Cache: Codable { var files: [String: Entry] }

    /// All token events across `~/.claude/projects/`, using the on-disk cache to skip re-parsing
    /// unchanged files. Re-parses only files whose `(size, mtime)` differs from the cache, then
    /// persists the updated cache (including dropping entries for deleted files).
    public static func allEvents(claudeHome: String? = nil, cacheDirectory: URL? = nil) -> [TokenEvent] {
        let home = claudeHome ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let projects = (home as NSString).appendingPathComponent("projects")
        let fm = FileManager.default

        let cacheURL = resolveCacheURL(cacheDirectory)
        var old = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }?.files ?? [:]

        var fresh: [String: Entry] = [:]
        var result: [TokenEvent] = []
        var reparsed = 0

        guard let dirs = try? fm.contentsOfDirectory(atPath: projects) else { return [] }
        for dir in dirs {
            let dirPath = (projects as NSString).appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = (dirPath as NSString).appendingPathComponent(file)
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
                let size = (attrs[.size] as? Int) ?? -1
                let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1

                if let hit = old[path], hit.size == size, hit.mtime == mtime {
                    fresh[path] = hit
                    result.append(contentsOf: hit.events)
                } else if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                    let events = JSONLParser.events(fromTranscript: contents)
                    fresh[path] = Entry(size: size, mtime: mtime, events: events)
                    result.append(contentsOf: events)
                    reparsed += 1
                }
            }
        }

        // Persist if anything changed (new/changed files, or deletions shrinking the set).
        if reparsed > 0 || fresh.count != old.count {
            try? fm.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(Cache(files: fresh)) {
                try? data.write(to: cacheURL, options: .atomic)
            }
        }
        return result
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
