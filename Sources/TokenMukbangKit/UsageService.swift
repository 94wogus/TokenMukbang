import Foundation

/// Orchestrates the full pipeline: Keychain → usage/profile API → sessions →
/// a single `UsageSnapshot`. Pure dependency-injected so it runs in tests and
/// previews without real credentials.
public struct UsageService: Sendable {
    private let credentials: CredentialProviding
    private let client: UsageFetching
    private let sessions: SessionDetector
    private let now: @Sendable () -> Date

    public init(
        credentials: CredentialProviding = SecurityCLICredentialStore(),
        client: UsageFetching = ClaudeAPIClient(),
        sessions: SessionDetector = SessionDetector(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.client = client
        self.sessions = sessions
        self.now = now
    }

    /// Build the snapshot. Never throws: failures (no creds, expired token,
    /// offline) are captured as `snapshot.error` so the UI degrades gracefully.
    public func snapshot() async -> UsageSnapshot {
        let timestamp = now()

        let creds: OAuthCredentials
        do {
            creds = try credentials.loadCredentials()
        } catch {
            return .failure(String(describing: error), at: timestamp)
        }

        if creds.isExpired(asOf: timestamp) {
            // Sessions are still useful even if the token is stale.
            return UsageSnapshot(
                capturedAt: timestamp,
                planLabel: nil,
                windows: [],
                sessions: detectSessions(),
                error: "OAuth token expired — run any Claude Code command to refresh it."
            )
        }

        do {
            async let usage = client.fetchUsage(token: creds.accessToken)
            async let profile = client.fetchProfile(token: creds.accessToken)
            let (u, p) = try await (usage, profile)
            return UsageSnapshot(
                capturedAt: timestamp,
                planLabel: p.planLabel,
                windows: windows(from: u, now: timestamp),
                sessions: detectSessions(),
                error: nil
            )
        } catch {
            return UsageSnapshot(
                capturedAt: timestamp,
                planLabel: nil,
                windows: [],
                sessions: detectSessions(),
                error: String(describing: error)
            )
        }
    }

    private func windows(from usage: Usage, now: Date) -> [UsageSnapshot.Window] {
        usage.displayWindows.map { kind, w in
            // Estimate when this window opened so risk can account for pacing
            // (smart coloring: absolute usage + projection).
            let start = w.resetsAt.addingTimeInterval(-kind.duration)
            let level = RiskScorer.level(
                utilization: w.utilization, windowStart: start, resetsAt: w.resetsAt, now: now
            )
            let pace = PaceForecast.hoursToFull(
                utilization: w.utilization, windowStart: start, resetsAt: w.resetsAt, now: now
            )
            return UsageSnapshot.Window(
                kind: kind.rawValue,
                label: kind.label,
                utilization: w.utilization,
                resetsAt: w.resetsAt,
                riskHex: level.hex,
                riskLabel: level.label,
                riskLevel: level.rawValue,
                isOver: w.utilization >= 100,
                paceWarningHours: pace
            )
        }
    }

    private func detectSessions() -> [UsageSnapshot.Session] {
        sessions.activeSessions().map {
            UsageSnapshot.Session(
                pid: $0.pid,
                projectName: $0.projectName,
                cwd: $0.cwd,
                tty: $0.tty,
                contextFraction: $0.contextFraction
            )
        }
    }
}
