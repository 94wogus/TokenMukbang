import Foundation

/// Best-effort "click a session → focus its terminal window".
///
/// Strategy: match the session's controlling TTY (e.g. `ttys016`) to a
/// Terminal.app or iTerm2 tab via AppleScript (each exposes its tty), then select
/// that tab/window. Unknown terminals fall back to merely activating the app.
/// Every failure is swallowed — focusing is a convenience, never a crash path.
public struct TerminalFocus: Sendable {
    private let runner: ProcessRunning

    public init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    /// Full device path AppleScript reports, e.g. `ttys016` → `/dev/ttys016`.
    public static func devicePath(forTTY tty: String) -> String {
        tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    /// AppleScript that finds the Terminal.app tab whose tty matches and selects it.
    public static func terminalAppScript(devicePath: String) -> String {
        """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(devicePath)" then
                        set selected of t to true
                        set index of w to 1
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "nomatch"
        """
    }

    /// AppleScript that finds the iTerm2 session whose tty matches and selects it.
    public static func iTermScript(devicePath: String) -> String {
        """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) is "\(devicePath)" then
                            select w
                            select t
                            select s
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "nomatch"
        """
    }

    public enum FocusOutcome: Equatable, Sendable {
        case focused(app: String)
        case activatedAppOnly(app: String)
        case noTTY
        case failed
    }

    // MARK: - GUI editor hosts (best-effort, ADR-0008)

    /// Editors that embed an integrated terminal. A session running inside one has no
    /// matchable terminal tty (the pty is owned by the editor), and there's no public
    /// API to focus the specific split pane — so the best we can do is bring the whole
    /// app forward. Markers match the `.app` bundle in an ancestor process's path.
    static let guiHosts: [(marker: String, app: String)] = [
        ("Visual Studio Code.app", "Visual Studio Code"),
        ("Code - Insiders.app", "Code - Insiders"),
        ("VSCodium.app", "VSCodium"),
        ("Cursor.app", "Cursor"),
        ("Windsurf.app", "Windsurf"),
    ]

    /// Map a single process command path to a GUI host app name, if it is one.
    static func guiHost(forComm comm: String) -> String? {
        for h in guiHosts where comm.contains(h.marker) { return h.app }
        return nil
    }

    /// Walk a pid's ancestry in `ps -axo pid=,ppid=,comm=` output and return the GUI
    /// editor app hosting it, if any. Pure → unit-tested. The `claude` process's own
    /// ancestors include the editor's helper process when run in an integrated terminal.
    public static func guiHostAppName(fromPsOutput ps: String, pid: Int32) -> String? {
        var parent: [Int32: Int32] = [:]
        var comm: [Int32: String] = [:]
        for line in ps.split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 3, let p = Int32(f[0]), let pp = Int32(f[1]) else { continue }
            parent[p] = pp
            comm[p] = f[2...].joined(separator: " ")
        }
        var cur: Int32? = pid
        var depth = 0
        while let c = cur, depth < 40 {
            if let cmd = comm[c], let host = guiHost(forComm: cmd) { return host }
            let next = parent[c]
            if next == nil || next == 0 || next == c { break }
            cur = next
            depth += 1
        }
        return nil
    }

    /// AppleScript that brings a named app forward (only if it's running), best-effort.
    static func activateAppScript(_ app: String) -> String {
        "tell application \"\(app)\"\nif it is running then\nactivate\nreturn \"ok\"\nend if\nend tell\nreturn \"nomatch\""
    }

    /// The GUI editor app hosting `pid`, if this session runs in an integrated terminal.
    private func guiHostApp(pid: Int32) -> String? {
        guard let r = try? runner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,ppid=,comm="]),
              r.exitCode == 0 else { return nil }
        return Self.guiHostAppName(fromPsOutput: r.standardOutput, pid: pid)
    }

    private func runScript(_ script: String) -> String? {
        guard let r = try? runner.run(executable: "/usr/bin/osascript", arguments: ["-e", script]),
              r.exitCode == 0 else { return nil }
        return r.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Terminals we attempt to focus, best-effort, in order.
    public enum SupportedTerminal: String, Sendable, CaseIterable {
        case terminal, iterm2, tmux, kitty, wezterm

        public var displayName: String {
            switch self {
            case .terminal: return "Terminal.app"
            case .iterm2: return "iTerm2"
            case .tmux: return "tmux"
            case .kitty: return "kitty"
            case .wezterm: return "WezTerm"
            }
        }
    }

    /// Find the WezTerm pane id whose tty matches, from `wezterm cli list --format json`
    /// output (array of objects with `pane_id` + `tty_name`). Pure → testable.
    public static func weztermPaneId(fromListJSON json: String, devicePath: String) -> Int? {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        for pane in arr {
            if let tty = pane["tty_name"] as? String, tty == devicePath,
               let id = pane["pane_id"] as? Int {
                return id
            }
        }
        return nil
    }

    private func focusWezterm(devicePath: String) -> Bool {
        guard let list = try? runner.run(executable: "/usr/bin/env",
                                         arguments: ["wezterm", "cli", "list", "--format", "json"]),
              list.exitCode == 0,
              let paneId = Self.weztermPaneId(fromListJSON: list.standardOutput, devicePath: devicePath)
        else { return false }
        let r = try? runner.run(executable: "/usr/bin/env",
                                arguments: ["wezterm", "cli", "activate-pane", "--pane-id", "\(paneId)"])
        return r?.exitCode == 0
    }

    private func focusKitty() -> Bool {
        // kitty remote control (requires `allow_remote_control yes`); best-effort focus.
        let r = try? runner.run(executable: "/usr/bin/env", arguments: ["kitty", "@", "focus-window"])
        return r?.exitCode == 0
    }

    private func focusTmux(tty: String) -> Bool {
        // Select the tmux window whose pane is on this tty, then switch client to it.
        let r = try? runner.run(executable: "/usr/bin/env",
                                arguments: ["tmux", "select-window", "-t", tty])
        return r?.exitCode == 0
    }

    /// Try to focus the terminal hosting `session`, across the supported terminals.
    @discardableResult
    public func focus(_ session: ActiveSession) -> FocusOutcome {
        // Editor-hosted sessions (VS Code, Cursor, …) have no matchable terminal tty —
        // bring the whole app forward and return *before* probing Terminal/iTerm, whose
        // scripts `activate` as a side effect and would otherwise steal focus (ADR-0008).
        if let host = guiHostApp(pid: session.pid),
           runScript(Self.activateAppScript(host)) == "ok" {
            return .activatedAppOnly(app: host)
        }

        guard let tty = session.tty else { return .noTTY }
        let device = Self.devicePath(forTTY: tty)

        if runScript(Self.terminalAppScript(devicePath: device)) == "ok" {
            return .focused(app: "Terminal")
        }
        if runScript(Self.iTermScript(devicePath: device)) == "ok" {
            return .focused(app: "iTerm2")
        }
        if focusWezterm(devicePath: device) { return .focused(app: "WezTerm") }
        if focusKitty() { return .focused(app: "kitty") }
        if focusTmux(tty: tty) { return .focused(app: "tmux") }

        // Fallback: bring the frontmost terminal app forward, if any is running.
        for app in ["iTerm2", "Terminal"] {
            if runScript(Self.activateAppScript(app)) == "ok" {
                return .activatedAppOnly(app: app)
            }
        }
        return .failed
    }
}
