import Foundation

/// Whether a Claude Code session is mid-task or has come to rest.
///
/// Read from the *last* message in the session's `.jsonl` transcript: a session
/// is `idle` (finished its turn, waiting for you) once its last assistant message
/// carries a terminal `stop_reason` (`end_turn` / `stop_sequence`). Anything else —
/// the last line is a `user` message (a fresh prompt or a returned tool result), or
/// the assistant stopped to call a tool (`tool_use`) — means it's still `working`.
///
/// The app edge-triggers a "session finished" notification on the `working → idle`
/// transition (ADR-0022). Pure + dependency-free → fully unit-tested.
public enum SessionActivity: String, Sendable, Equatable {
    case working
    case idle

    /// `stop_reason` values that mean the turn truly ended (not a tool hand-off).
    static let terminalStopReasons: Set<String> = ["end_turn", "stop_sequence"]
}

public enum SessionActivityReader {
    /// Derive activity from a transcript's text. Returns `nil` when the transcript
    /// has no decodable assistant/user message yet (treat as "unknown", don't notify).
    public static func activity(fromTranscript contents: String) -> SessionActivity? {
        var lastRole: String?
        var lastAssistantStopReason: String?
        contents.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  role == "assistant" || role == "user"
            else { return }
            lastRole = role
            if role == "assistant" {
                // `stop_reason` is null while streaming and on tool-call turns.
                lastAssistantStopReason = message["stop_reason"] as? String
            }
        }
        guard let role = lastRole else { return nil }
        // The assistant only comes to rest when its *latest* message ended the turn.
        if role == "assistant",
           let reason = lastAssistantStopReason,
           SessionActivity.terminalStopReasons.contains(reason) {
            return .idle
        }
        return .working
    }

    /// Read a transcript file and derive its activity, if readable.
    public static func activity(transcriptPath: String) -> SessionActivity? {
        guard let contents = try? String(contentsOfFile: transcriptPath, encoding: .utf8)
        else { return nil }
        return activity(fromTranscript: contents)
    }
}
