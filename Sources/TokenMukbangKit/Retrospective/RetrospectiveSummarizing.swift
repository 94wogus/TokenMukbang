import Foundation

/// The content layer (B) seam: turn a period's conversation digest into `RetroTopics`.
/// Injectable so tests substitute a fake (ADR-0006). The live implementation
/// (`ClaudeCLISummarizer`) shells out to the local `claude` CLI (ADR-0020).
///
/// Returns `nil` when summarization is unavailable (CLI missing, failure, empty digest)
/// so the UI degrades to the metadata-only (A) retrospective.
public protocol RetrospectiveSummarizing: Sendable {
    func summarize(digest: String, now: Date) async -> RetroTopics?
}

/// Collects a compact, period-scoped digest of **user** prompts from Claude Code
/// transcripts — the input the content summarizer (B) sends to the `claude` CLI.
///
/// This reads conversation *text* (not token counts), so it is deliberately separate
/// from `JSONLParser` (which extracts token usage, layer A). It never reads or carries
/// the OAuth token.
public enum TranscriptDigest {
    /// One user prompt and the project it belongs to.
    public struct Prompt: Sendable, Equatable {
        public let project: String
        public let text: String
        public init(project: String, text: String) { self.project = project; self.text = text }
    }

    /// Build a digest of user prompts in `[periodStart, periodEnd)` from every transcript
    /// under `~/.claude/projects/`, **balanced across projects** so a single chatty project
    /// can't monopolize the budget (the old front-truncation made the summary reflect only
    /// whichever project was read first). Prompts are round-robined across projects and
    /// `[project]`-labeled so the summarizer can attribute topics. Capped at `maxChars`.
    public static func build(periodStart: Date,
                             periodEnd: Date,
                             claudeHome: String? = nil,
                             maxChars: Int = 16_000) -> String {
        let (byProject, order) = collect(periodStart: periodStart, periodEnd: periodEnd, claudeHome: claudeHome)
        return assemble(byProject: byProject, order: order, maxChars: maxChars)
    }

    /// Walk every transcript under `~/.claude/projects/` and group period-scoped user
    /// prompts by project (preserving first-seen order). Returned separately from `build`
    /// so the coach can use the per-project **prompt counts** (a steering signal —
    /// few prompts + many tokens ⇒ automated/long-context work) alongside a sampled digest.
    public static func collect(periodStart: Date,
                               periodEnd: Date,
                               claudeHome: String? = nil) -> (byProject: [String: [String]], order: [String]) {
        let home = claudeHome ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let projects = (home as NSString).appendingPathComponent("projects")
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projects).sorted() else { return ([:], []) }

        var byProject: [String: [String]] = [:]
        var order: [String] = []
        for dir in dirs {
            let dirPath = (projects as NSString).appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath).sorted() else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = (dirPath as NSString).appendingPathComponent(file)
                guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                for p in userPrompts(fromTranscript: contents, periodStart: periodStart, periodEnd: periodEnd) {
                    if byProject[p.project] == nil { order.append(p.project) }
                    byProject[p.project, default: []].append(p.text)
                }
            }
        }
        return (byProject, order)
    }

    /// Round-robin across projects (one prompt each per round) until the budget is spent,
    /// so every active project is represented before any project gets a second turn.
    ///
    /// `limitTo` (when non-nil) restricts the digest to that set of projects. The coach prompt
    /// only tabulates the heaviest *consumed-token* projects (`RetrospectiveMetrics.coachedProjects`),
    /// so the sample prompts must be filtered to the same set — otherwise a prompt-only project
    /// (user typed in it but it ate ~0 tokens, so it's absent from the metrics/Menu) leaks into the
    /// sample and the coach cites a project the user can't see in their breakdown.
    public static func assemble(byProject: [String: [String]], order: [String], maxChars: Int,
                                limitTo allowed: Set<String>? = nil) -> String {
        let order = allowed.map { a in order.filter { a.contains($0) } } ?? order
        var digest = ""
        var round = 0
        var added = true
        while added {
            added = false
            for project in order {
                guard let prompts = byProject[project], round < prompts.count else { continue }
                added = true
                let line = "[\(project)] " + prompts[round]
                if digest.count + line.count + 1 > maxChars {
                    return digest.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                digest += line + "\n"
            }
            round += 1
        }
        return digest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract user prompts (with their project) from one transcript, scoped to the period.
    /// A line with a timestamp is kept only if it falls in `[periodStart, periodEnd)`;
    /// a line without a timestamp is kept best-effort (some formats omit it on user turns).
    /// Project = the line's `cwd` last path component (matches `JSONLParser`), else "unknown".
    public static func userPrompts(fromTranscript contents: String,
                                   periodStart: Date,
                                   periodEnd: Date) -> [Prompt] {
        var out: [Prompt] = []
        contents.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "user",
                  let message = obj["message"] as? [String: Any]
            else { return }

            if let tsRaw = obj["timestamp"] as? String, let ts = ClaudeJSON.parseISO8601(tsRaw) {
                guard ts >= periodStart && ts < periodEnd else { return }
            }

            guard let text = extractText(message["content"]) else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let cwd = (obj["cwd"] as? String) ?? ""
            let project = cwd.isEmpty ? "unknown" : (cwd as NSString).lastPathComponent
            out.append(Prompt(project: project, text: trimmed))
        }
        return out
    }

    /// `content` is either a plain string or an array of `{type:"text", text:"…"}` blocks.
    private static func extractText(_ content: Any?) -> String? {
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            let texts = blocks.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            return texts.isEmpty ? nil : texts.joined(separator: " ")
        }
        return nil
    }
}
