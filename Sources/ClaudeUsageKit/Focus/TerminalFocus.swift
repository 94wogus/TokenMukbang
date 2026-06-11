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

    private func runScript(_ script: String) -> String? {
        guard let r = try? runner.run(executable: "/usr/bin/osascript", arguments: ["-e", script]),
              r.exitCode == 0 else { return nil }
        return r.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Try to focus the terminal hosting `session`.
    @discardableResult
    public func focus(_ session: ActiveSession) -> FocusOutcome {
        guard let tty = session.tty else { return .noTTY }
        let device = Self.devicePath(forTTY: tty)

        if runScript(Self.terminalAppScript(devicePath: device)) == "ok" {
            return .focused(app: "Terminal")
        }
        if runScript(Self.iTermScript(devicePath: device)) == "ok" {
            return .focused(app: "iTerm2")
        }
        // Fallback: bring the frontmost terminal app forward, if either is running.
        for app in ["iTerm2", "Terminal"] {
            if runScript("tell application \"\(app)\"\nif it is running then\nactivate\nreturn \"ok\"\nend if\nend tell\nreturn \"nomatch\"") == "ok" {
                return .activatedAppOnly(app: app)
            }
        }
        return .failed
    }
}
