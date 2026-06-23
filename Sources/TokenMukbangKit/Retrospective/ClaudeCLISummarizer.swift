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
    (per-project "drain" tokens broken into output / fresh-input / cache-write, user-prompts, \
    tokens/prompt, model) plus a few sample prompts. Analyze HOW EFFICIENTLY they spent their \
    usage and give specific, actionable advice to spend it BETTER — do NOT just describe what \
    they did.

    WHAT DRIVES THE COST (use this mental model; "drain" = output + fresh-input + cache-write):
    - Frame cost by the user's Plan (shown in the data). For subscription plans (Max/Pro/Team) the \
      cost is BURNING THE SHARED 5h/7d USAGE WINDOW FASTER (hitting limits / fewer hours of \
      runway) — NOT dollars; only talk dollars for pay-per-token API usage.
    - What burns the window, in rank order: (1) MODEL TIER — Opus burns it fastest; the same work \
      on Sonnet/Haiku costs far less. This is the biggest lever. (2) OUTPUT tokens — full price, \
      the most expensive per token. (3) FRESH (uncached) INPUT. (4) CACHE-WRITE — re-caching \
      context after a >5-min idle gap expired the prior cache.
    - Cache READS do NOT drain the window and do NOT count toward the limit; they are excluded from \
      "drain". NEVER claim a high cache-read rate is a cost, a "tax", or something to fix, and NEVER \
      tell the user to /clear to cut cache reads. (You MAY still suggest /clear or splitting a \
      session for FOCUS between unrelated tasks — never tied to cache reads.)

    Then look for:
    - Model choice: a project with a high Opus share doing mechanical/bulk work → route it to \
      Sonnet/Haiku (the biggest saving).
    - Automation: low user-prompts + high drain ⇒ long auto-loops (e.g. Ralph) running with little \
      steering — flag the project where this dominates; suggest iteration caps / checkpoints.
    - Efficient patterns: a project with many prompts relative to its drain is tight, well-steered \
      work — mirror it back as the pattern to repeat; repeated work could become a saved prompt/skill.
    - Pacing: time concentration, bursty vs steady.

    HARD RULES:
    - Every number you state MUST be copied or directly arithmetic-derived from the metrics below. \
      NEVER invent a multiplier, an "Nx" figure, or a per-turn tax count that isn't in the data.
    - ONLY reference project names that appear in the "Per project" list below. Never name a project \
      that isn't in the data.

    Respond in English:
    line 1: a one-sentence TL;DR naming the single biggest opportunity to spend the usage window \
    better (model tier or output — never cache reads).
    then up to 6 lines, each starting with "- ", a concrete recommendation referencing a \
    specific project or metric from the data. No other commentary.

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
