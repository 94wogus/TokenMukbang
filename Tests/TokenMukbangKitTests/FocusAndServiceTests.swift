import XCTest
@testable import TokenMukbangKit

/// Records the commands a fake runner was asked to execute, returning scripted output.
final class FakeRunner: ProcessRunning, @unchecked Sendable {
    var responses: [(match: String, result: ProcessResult)] = []
    private(set) var calls: [[String]] = []

    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        calls.append([executable] + arguments)
        let joined = ([executable] + arguments).joined(separator: " ")
        for r in responses where joined.contains(r.match) {
            return r.result
        }
        return ProcessResult(exitCode: 1, standardOutput: "", standardError: "no match")
    }
}

struct StubCredentials: CredentialProviding {
    let creds: OAuthCredentials
    func loadCredentials() throws -> OAuthCredentials { creds }
}

struct StubFetcher: UsageFetching {
    let usage: Usage
    let profile: Profile
    func fetchUsage(token: String) async throws -> Usage { usage }
    func fetchProfile(token: String) async throws -> Profile { profile }
}

final class FocusTests: XCTestCase {
    func testDevicePath() {
        XCTAssertEqual(TerminalFocus.devicePath(forTTY: "ttys016"), "/dev/ttys016")
        XCTAssertEqual(TerminalFocus.devicePath(forTTY: "/dev/ttys016"), "/dev/ttys016")
    }

    func testScriptsEmbedDevicePath() {
        XCTAssertTrue(TerminalFocus.terminalAppScript(devicePath: "/dev/ttys016").contains("/dev/ttys016"))
        XCTAssertTrue(TerminalFocus.iTermScript(devicePath: "/dev/ttys016").contains("/dev/ttys016"))
    }

    func testFocusMatchesTerminalTab() {
        let runner = FakeRunner()
        runner.responses = [("Terminal", ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))]
        let focus = TerminalFocus(runner: runner)
        let session = ActiveSession(pid: 1, tty: "ttys016", cwd: "/x", contextFraction: nil)
        XCTAssertEqual(focus.focus(session), .focused(app: "Terminal"))
    }

    func testFocusNoTTY() {
        let focus = TerminalFocus(runner: FakeRunner())
        let session = ActiveSession(pid: 1, tty: nil, cwd: "/x", contextFraction: nil)
        XCTAssertEqual(focus.focus(session), .noTTY)
    }

    func testSupportedTerminalsIncludeExtras() {
        let names = Set(TerminalFocus.SupportedTerminal.allCases.map(\.rawValue))
        XCTAssertEqual(TerminalFocus.SupportedTerminal.allCases.count, 5)
        XCTAssertTrue(names.isSuperset(of: ["terminal", "iterm2", "tmux", "kitty", "wezterm"]))
    }

    func testWeztermPaneMatchingByTTY() {
        let json = """
        [{"pane_id":3,"tty_name":"/dev/ttys009"},{"pane_id":7,"tty_name":"/dev/ttys016"}]
        """
        XCTAssertEqual(TerminalFocus.weztermPaneId(fromListJSON: json, devicePath: "/dev/ttys016"), 7)
        XCTAssertNil(TerminalFocus.weztermPaneId(fromListJSON: json, devicePath: "/dev/ttys099"))
        XCTAssertNil(TerminalFocus.weztermPaneId(fromListJSON: "not json", devicePath: "/dev/ttys016"))
    }

    // MARK: - GUI host (VS Code / editor integrated terminal) — ADR-0022

    /// `ps -axo pid=,ppid=,comm=`-style output: claude → shell → VS Code helper → launchd.
    private let vscodePs = """
    901 870 /opt/homebrew/bin/node /opt/homebrew/bin/claude
    870 540 -zsh
    540 1 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Renderer).app/Contents/MacOS/Code Helper (Renderer)
    1 0 /sbin/launchd
    """

    func testGUIHostWalksAncestryToVSCode() {
        XCTAssertEqual(TerminalFocus.guiHostAppName(fromPsOutput: vscodePs, pid: 901), "Visual Studio Code")
    }

    func testGUIHostNilForPlainTerminalSession() {
        // claude → shell → Terminal.app's login → launchd: no editor in the chain.
        let ps = """
        901 870 /opt/homebrew/bin/node /opt/homebrew/bin/claude
        870 540 -zsh
        540 1 login -fp wogus
        1 0 /sbin/launchd
        """
        XCTAssertNil(TerminalFocus.guiHostAppName(fromPsOutput: ps, pid: 901))
    }

    func testGUIHostCursorAndStopsAtMissingParent() {
        let ps = "901 870 /Applications/Cursor.app/Contents/MacOS/Cursor Helper"
        XCTAssertEqual(TerminalFocus.guiHostAppName(fromPsOutput: ps, pid: 901), "Cursor")
        XCTAssertNil(TerminalFocus.guiHostAppName(fromPsOutput: ps, pid: 555)) // unknown pid
    }

    func testFocusActivatesEditorBeforeProbingTerminals() {
        let runner = FakeRunner()
        runner.responses = [
            ("pid=,ppid=,comm=", ProcessResult(exitCode: 0, standardOutput: vscodePs, standardError: "")),
            ("Visual Studio Code", ProcessResult(exitCode: 0, standardOutput: "ok", standardError: "")),
        ]
        let focus = TerminalFocus(runner: runner)
        let session = ActiveSession(pid: 901, tty: "ttys016", cwd: "/x", contextFraction: nil)
        XCTAssertEqual(focus.focus(session), .activatedAppOnly(app: "Visual Studio Code"))
        // It must not have fallen through to the Terminal.app tty-match script.
        XCTAssertFalse(runner.calls.contains { $0.joined(separator: " ").contains("tabs of w") })
    }
}

final class SessionActivityTests: XCTestCase {
    private func line(role: String, stopReason: String?) -> String {
        var message: [String: Any] = ["role": role]
        if role == "assistant" {
            message["model"] = "claude-opus-4-8"
            message["stop_reason"] = stopReason as Any  // NSNull-free: omitted when nil below
            if stopReason == nil { message["stop_reason"] = NSNull() }
            message["usage"] = ["input_tokens": 10]
        }
        let obj: [String: Any] = ["type": role, "message": message]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    func testEndTurnIsIdle() {
        let t = [line(role: "user", stopReason: nil),
                 line(role: "assistant", stopReason: "end_turn")].joined(separator: "\n")
        XCTAssertEqual(SessionActivityReader.activity(fromTranscript: t), .idle)
    }

    func testToolUseIsWorking() {
        let t = [line(role: "user", stopReason: nil),
                 line(role: "assistant", stopReason: "tool_use")].joined(separator: "\n")
        XCTAssertEqual(SessionActivityReader.activity(fromTranscript: t), .working)
    }

    func testTrailingUserLineIsWorking() {
        // Assistant ended a turn, then a new user/tool_result line landed → working again.
        let t = [line(role: "assistant", stopReason: "end_turn"),
                 line(role: "user", stopReason: nil)].joined(separator: "\n")
        XCTAssertEqual(SessionActivityReader.activity(fromTranscript: t), .working)
    }

    func testNullStopReasonIsWorking() {
        let t = line(role: "assistant", stopReason: nil)
        XCTAssertEqual(SessionActivityReader.activity(fromTranscript: t), .working)
    }

    func testEmptyTranscriptIsNil() {
        XCTAssertNil(SessionActivityReader.activity(fromTranscript: ""))
        XCTAssertNil(SessionActivityReader.activity(fromTranscript: "{\"type\":\"summary\"}"))
    }
}

final class ServiceTests: XCTestCase {
    private func sampleUsage() -> Usage {
        Usage(
            fiveHour: RateLimitWindow(utilization: 8, resetsAt: Date(timeIntervalSince1970: 2000)),
            sevenDay: RateLimitWindow(utilization: 31, resetsAt: Date(timeIntervalSince1970: 9000)),
            sevenDayOpus: nil,
            sevenDaySonnet: nil
        )
    }

    private func sampleProfile() -> Profile {
        Profile(
            account: .init(displayName: "Tester", email: "t@e.com", hasClaudeMax: true, hasClaudePro: false),
            organization: .init(organizationType: "claude_max", rateLimitTier: "x", subscriptionStatus: "active")
        )
    }

    func testSnapshotHappyPath() async {
        let creds = OAuthCredentials(accessToken: "tok", refreshToken: nil, expiresAt: 9_999_999_999_000, scopes: nil, subscriptionType: "max")
        let service = UsageService(
            credentials: StubCredentials(creds: creds),
            client: StubFetcher(usage: sampleUsage(), profile: sampleProfile()),
            sessions: SessionDetector(runner: FakeRunner()),
            now: { Date(timeIntervalSince1970: 1000) }
        )
        let snap = await service.snapshot()
        XCTAssertNil(snap.error)
        XCTAssertEqual(snap.planLabel, "Max")
        XCTAssertEqual(snap.windows.count, 2)
        XCTAssertEqual(snap.headlineWindow?.kind, "seven_day") // 31% > 8%
    }

    func testSnapshotMissingCredentialsIsGraceful() async {
        struct FailingCreds: CredentialProviding {
            func loadCredentials() throws -> OAuthCredentials { throw CredentialError.notFound }
        }
        let service = UsageService(
            credentials: FailingCreds(),
            client: StubFetcher(usage: sampleUsage(), profile: sampleProfile()),
            sessions: SessionDetector(runner: FakeRunner()),
            now: { Date(timeIntervalSince1970: 1000) }
        )
        let snap = await service.snapshot()
        XCTAssertNotNil(snap.error)
        XCTAssertTrue(snap.windows.isEmpty)
    }

    func testSnapshotExpiredTokenSkipsAPIButKeepsSessions() async {
        let creds = OAuthCredentials(accessToken: "tok", refreshToken: nil, expiresAt: 1000, scopes: nil, subscriptionType: "max")
        let service = UsageService(
            credentials: StubCredentials(creds: creds),
            client: StubFetcher(usage: sampleUsage(), profile: sampleProfile()),
            sessions: SessionDetector(runner: FakeRunner()),
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
        let snap = await service.snapshot()
        XCTAssertNotNil(snap.error)
        XCTAssertTrue(snap.error?.contains("expired") ?? false)
    }
}

final class FormattingTests: XCTestCase {
    func testCountdown() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Formatting.countdown(to: Date(timeIntervalSince1970: 8040), from: now), "2h 14m")
        XCTAssertEqual(Formatting.countdown(to: Date(timeIntervalSince1970: 2820), from: now), "47m")
        XCTAssertEqual(Formatting.countdown(to: Date(timeIntervalSince1970: -5), from: now), "now")
        XCTAssertEqual(Formatting.countdown(to: Date(timeIntervalSince1970: 180_000), from: now), "2d 2h")
    }

    func testPercentAndBar() {
        XCTAssertEqual(Formatting.percent(72.0), "72%")
        XCTAssertEqual(Formatting.percent(fraction: 0.41), "41%")
        XCTAssertEqual(Formatting.bar(fraction: 1.0), "▓▓▓▓▓")
        XCTAssertEqual(Formatting.bar(fraction: 0.0), "░░░░░")
    }
}
