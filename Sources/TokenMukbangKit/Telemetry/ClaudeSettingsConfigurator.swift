import Foundation

/// Safely wires Claude Code's `~/.claude/settings.json` to export OTLP telemetry to our
/// **local** receiver (ADR-0024 Slice 1) — so the user doesn't paste an env block by hand.
///
/// Safety is the whole point:
/// - **Merge, never clobber.** Only the keys in `managedKeys` are added/removed; every other
///   `env` key and top-level key is preserved.
/// - **Never overwrite unparseable JSON.** If the file exists but doesn't parse (comments/
///   JSONC/corruption), we touch nothing and return `.needsManualEdit` so the app can show the
///   block to paste — we never destroy a config we can't safely read.
public enum ClaudeSettingsConfigurator {
    /// The OTLP env keys this configurator owns. Disabling removes exactly these.
    public static let managedKeys = [
        "CLAUDE_CODE_ENABLE_TELEMETRY",
        "OTEL_METRICS_EXPORTER",
        "OTEL_LOGS_EXPORTER",
        "OTEL_EXPORTER_OTLP_PROTOCOL",
        "OTEL_EXPORTER_OTLP_ENDPOINT",
        "OTEL_METRIC_EXPORT_INTERVAL",
        "OTEL_LOGS_EXPORT_INTERVAL",
    ]

    /// The env block pointing Claude Code at our loopback receiver (no auth — loopback).
    /// The export intervals are tightened from Claude Code's defaults (metrics 60s / logs 5s)
    /// so the local dashboard updates near-real-time — the data flows to our own loopback, so
    /// the extra frequency costs nothing off-host (verified against monitoring-usage docs).
    public static func envBlock(port: Int) -> [String: String] {
        [
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
            "OTEL_METRICS_EXPORTER": "otlp",
            "OTEL_LOGS_EXPORTER": "otlp",
            "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
            "OTEL_EXPORTER_OTLP_ENDPOINT": "http://127.0.0.1:\(port)",
            "OTEL_METRIC_EXPORT_INTERVAL": "10000",   // 10s (default 60000)
            "OTEL_LOGS_EXPORT_INTERVAL": "2000",      // 2s  (default 5000)
        ]
    }

    public enum Outcome: Equatable, Sendable {
        case wrote            // enabled: our keys merged in
        case removed          // disabled: our keys taken out
        case unchanged        // already in the desired state
        case needsManualEdit  // file exists but unparseable, or write failed — don't clobber
    }

    /// Pure merge: return `settings` with our env block added (`enabled`) or our managed keys
    /// removed (`!enabled`). Other env keys and top-level keys are preserved; an emptied `env`
    /// is dropped entirely.
    public static func apply(enabled: Bool, port: Int, into settings: [String: Any]) -> [String: Any] {
        var s = settings
        var env = (s["env"] as? [String: Any]) ?? [:]
        if enabled {
            for (k, v) in envBlock(port: port) { env[k] = v }
        } else {
            for k in managedKeys { env.removeValue(forKey: k) }
        }
        if env.isEmpty { s.removeValue(forKey: "env") } else { s["env"] = env }
        return s
    }

    /// Read → merge → write the settings file. Injectable path for tests. Never overwrites a
    /// file it can't parse.
    @discardableResult
    public static func configure(enabled: Bool, port: Int, settingsPath: String) -> Outcome {
        let fm = FileManager.default
        var existing: [String: Any] = [:]
        if fm.fileExists(atPath: settingsPath) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return .needsManualEdit }   // exists but unparseable → never clobber
            existing = obj
        } else if !enabled {
            return .unchanged                  // nothing to remove from a missing file
        }

        let updated = apply(enabled: enabled, port: port, into: existing)
        if NSDictionary(dictionary: updated).isEqual(to: existing) { return .unchanged }

        guard let out = try? JSONSerialization.data(
            withJSONObject: updated, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return .needsManualEdit }
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        do {
            try out.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
            return enabled ? .wrote : .removed
        } catch {
            return .needsManualEdit
        }
    }
}
