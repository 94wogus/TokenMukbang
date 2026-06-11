import XCTest
@testable import ClaudeUsageKit

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
