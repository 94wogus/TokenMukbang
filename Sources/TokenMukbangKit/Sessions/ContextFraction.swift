import Foundation

/// Computes how full a Claude Code session's context window is by reading the
/// last assistant `usage` block from its `.jsonl` transcript.
public enum ContextFraction {
    /// Context tokens currently resident = the full prompt size on the last turn:
    /// fresh input + cache creation + cache reads.
    public static func contextTokens(fromUsage usage: [String: Any]) -> Int? {
        let input = usage["input_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let total = input + cacheCreate + cacheRead
        return total > 0 ? total : nil
    }

    /// Heuristic context-window size: models stream >200k only on the 1M variant,
    /// so anything above the 200k ceiling implies the 1M window.
    public static func windowSize(forTokens tokens: Int, model: String?) -> Int {
        if let model, model.contains("[1m]") || model.contains("-1m") { return 1_000_000 }
        return tokens > 200_000 ? 1_000_000 : 200_000
    }

    /// Parse a transcript's last assistant usage and return (tokens, window, model).
    public static func parseTranscript(_ contents: String) -> (tokens: Int, window: Int, model: String?)? {
        var lastUsage: [String: Any]?
        var lastModel: String?
        contents.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { return }
            lastUsage = usage
            lastModel = message["model"] as? String
        }
        guard let usage = lastUsage, let tokens = contextTokens(fromUsage: usage) else { return nil }
        return (tokens, windowSize(forTokens: tokens, model: lastModel), lastModel)
    }

    /// 0...1 fraction of the window consumed for a transcript file, if readable.
    public static func fraction(transcriptPath: String) -> Double? {
        guard let contents = try? String(contentsOfFile: transcriptPath, encoding: .utf8),
              let parsed = parseTranscript(contents)
        else { return nil }
        return min(1.0, Double(parsed.tokens) / Double(parsed.window))
    }
}
