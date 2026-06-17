import Foundation

/// Live content-summarizer (B): shells out to the locally-installed `claude` CLI to turn
/// a conversation digest into `RetroTopics` (ADR-0020).
///
/// Invariants:
///   • The `claude` CLI **self-authenticates** — this type never reads, receives, or passes
///     the OAuth token (ADR-0002 preserved). It has no `CredentialProviding` dependency.
///   • The subprocess goes through the injected `ProcessRunning` seam (ADR-0006), never a
///     direct `Process`.
///   • It only runs when explicitly invoked (on demand) — the 먹방 paradox (ADR-0020).
public struct ClaudeCLISummarizer: RetrospectiveSummarizing {
    private let runner: ProcessRunning
    private let claudePath: String

    /// Candidate install locations for the `claude` CLI, checked in order.
    public static let candidatePaths: [String] = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/local/claude"),
    ]

    /// First candidate path that exists, or `nil` if the CLI isn't installed (→ B unavailable).
    public static func resolvedPath() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public init(runner: ProcessRunning, claudePath: String) {
        self.runner = runner
        self.claudePath = claudePath
    }

    private static let instruction = """
    You are a Claude Code usage coach. Below are a developer's usage metrics for one day \
    (per-project tokens, user-prompts, tokens/prompt, cache-read/turn, model) plus a few \
    sample prompts. Analyze HOW EFFICIENTLY they used their tokens and give specific, \
    actionable advice to use them BETTER — do NOT just describe what they did. Consider:
    - Cost: model choice (e.g. Opus where Sonnet/Haiku would do), cache reuse, high tokens/prompt.
    - Session/context hygiene: high cache-read/turn ⇒ ballooned context; when to /clear or split.
    - Workflow: low prompts + high tokens ⇒ automation/long auto-loops (e.g. Ralph) — flag if it \
      dominates; repeated work that could become a saved prompt/skill.
    - Pacing: time concentration, bursty vs steady.
    Respond in English:
    line 1: a one-sentence TL;DR naming the single biggest opportunity to use tokens better.
    then up to 6 lines, each starting with "- ", a concrete recommendation referencing a \
    specific project or metric. No other commentary.

    Data:
    """

    public func summarize(digest: String, now: Date) async -> RetroTopics? {
        let trimmedDigest = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDigest.isEmpty else { return nil }

        let prompt = Self.instruction + "\n\n" + trimmedDigest
        guard let result = try? runner.run(executable: claudePath, arguments: ["-p", prompt]),
              result.exitCode == 0
        else { return nil }

        return Self.parse(result.standardOutput, now: now)
    }

    /// Parse the CLI's plain-text reply: first non-empty line = summary, `- `-prefixed
    /// lines = themes. Returns `nil` if there's no usable summary line.
    static func parse(_ output: String, now: Date) -> RetroTopics? {
        var summary: String?
        var themes: [String] = []
        output.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                themes.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if summary == nil {
                summary = trimmed
            }
        }
        guard let summary, !summary.isEmpty else { return nil }
        return RetroTopics(summary: summary, themes: themes, generatedAt: now, source: .claudeCLI)
    }
}
