import Foundation

/// A currently-running Claude Code session.
public struct ActiveSession: Sendable, Equatable, Identifiable {
    public let pid: Int32
    /// Controlling terminal, e.g. `ttys016` (nil/`??` when detached).
    public let tty: String?
    /// Working directory of the `claude` process.
    public let cwd: String
    /// 0...1 context-window fill, when the transcript could be read.
    public let contextFraction: Double?

    public var id: Int32 { pid }

    /// Last path component of the cwd — a short, recognizable project name.
    public var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    public init(pid: Int32, tty: String?, cwd: String, contextFraction: Double?) {
        self.pid = pid
        self.tty = tty
        self.cwd = cwd
        self.contextFraction = contextFraction
    }
}

/// Discovers active Claude Code sessions from running processes + transcript dirs.
public struct SessionDetector: Sendable {
    private let runner: ProcessRunning
    private let claudeHome: String

    public init(runner: ProcessRunning = SystemProcessRunner(), claudeHome: String? = nil) {
        self.runner = runner
        self.claudeHome = claudeHome
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
    }

    /// Encode a cwd into Claude Code's transcript-dir name: `/A/B` → `-A-B`.
    public static func encodeProjectDir(_ cwd: String) -> String {
        var s = cwd.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: ".", with: "-")
        if !s.hasPrefix("-") { s = "-" + s }
        return s
    }

    /// Parse `ps -axo pid=,tty=,comm=` output, keeping only `claude` processes.
    /// Exposed for testing.
    public static func parsePsOutput(_ output: String) -> [(pid: Int32, tty: String?)] {
        var result: [(Int32, String?)] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3 else { continue }
            guard let pid = Int32(fields[0]) else { continue }
            let comm = fields[2...].joined(separator: " ")
            guard comm == "claude" || comm.hasSuffix("/claude") else { continue }
            let ttyRaw = String(fields[1])
            let tty = (ttyRaw == "??" || ttyRaw == "?") ? nil : ttyRaw
            result.append((pid, tty))
        }
        return result
    }

    /// Resolve the newest transcript `.jsonl` for a project cwd, if any.
    public func newestTranscript(forCwd cwd: String) -> String? {
        let dir = (claudeHome as NSString)
            .appendingPathComponent("projects")
        let projectDir = (dir as NSString)
            .appendingPathComponent(Self.encodeProjectDir(cwd))
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: projectDir) else { return nil }
        let jsonls = entries.filter { $0.hasSuffix(".jsonl") }
            .map { (projectDir as NSString).appendingPathComponent($0) }
        return jsonls.max { lhs, rhs in
            let lm = (try? fm.attributesOfItem(atPath: lhs)[.modificationDate] as? Date) ?? nil
            let rm = (try? fm.attributesOfItem(atPath: rhs)[.modificationDate] as? Date) ?? nil
            return (lm ?? .distantPast) < (rm ?? .distantPast)
        }
    }

    /// Working directory of a pid via `lsof`.
    private func cwd(forPid pid: Int32) -> String? {
        guard let r = try? runner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        ), r.exitCode == 0 else { return nil }
        for line in r.standardOutput.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// Enumerate active sessions. Best-effort: a process whose cwd can't be read
    /// is skipped rather than failing the whole scan.
    public func activeSessions() -> [ActiveSession] {
        guard let ps = try? runner.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,tty=,comm="]
        ), ps.exitCode == 0 else { return [] }

        return Self.parsePsOutput(ps.standardOutput).compactMap { entry in
            guard let cwd = cwd(forPid: entry.pid) else { return nil }
            let fraction = newestTranscript(forCwd: cwd).flatMap { ContextFraction.fraction(transcriptPath: $0) }
            return ActiveSession(pid: entry.pid, tty: entry.tty, cwd: cwd, contextFraction: fraction)
        }
        .sorted { ($0.contextFraction ?? 0) > ($1.contextFraction ?? 0) }
    }
}
