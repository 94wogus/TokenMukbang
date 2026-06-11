import Foundation

/// One assistant turn's token consumption, parsed from a Claude Code transcript.
public struct TokenEvent: Sendable, Equatable {
    public let timestamp: Date
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheCreationTokens: Int
    public let project: String

    public init(timestamp: Date, model: String, inputTokens: Int, outputTokens: Int,
                cacheReadTokens: Int, cacheCreationTokens: Int, project: String) {
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.project = project
    }

    /// All tokens that passed through the model this turn.
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// Which 먹방 cast member ate this turn.
    public var cast: ModelCast? { ModelCast.forModel(model) }
}

/// Tail-reads Claude Code `.jsonl` transcripts and extracts per-turn token usage
/// — the data behind TokenEater's token-consumption History browser.
public enum JSONLParser {
    /// Parse assistant token events from one transcript's contents.
    /// Each line is a JSON object with top-level `timestamp`/`cwd`/`type` and
    /// `message.{model, usage}`.
    public static func events(fromTranscript contents: String) -> [TokenEvent] {
        var events: [TokenEvent] = []
        contents.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { return }

            guard let tsRaw = obj["timestamp"] as? String,
                  let timestamp = ClaudeJSON.parseISO8601(tsRaw)
            else { return }

            let cwd = (obj["cwd"] as? String) ?? ""
            let project = cwd.isEmpty ? "unknown" : (cwd as NSString).lastPathComponent

            events.append(TokenEvent(
                timestamp: timestamp,
                model: (message["model"] as? String) ?? "unknown",
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                outputTokens: usage["output_tokens"] as? Int ?? 0,
                cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                project: project
            ))
        }
        return events
    }

    /// Parse every transcript under `~/.claude/projects/` (best-effort).
    public static func allEvents(claudeHome: String? = nil) -> [TokenEvent] {
        let home = claudeHome ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let projects = (home as NSString).appendingPathComponent("projects")
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projects) else { return [] }
        var events: [TokenEvent] = []
        for dir in dirs {
            let dirPath = (projects as NSString).appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = (dirPath as NSString).appendingPathComponent(file)
                if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                    events.append(contentsOf: Self.events(fromTranscript: contents))
                }
            }
        }
        return events
    }
}
