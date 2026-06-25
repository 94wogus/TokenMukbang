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
    ///
    /// `thresholds` (the user's warning/critical %, ADR-0013) drive the
    /// per-window risk level baked into the snapshot — so menu bar, popover
    /// cards and the widget all color off the same threshold-aware level.
    public func snapshot(thresholds: RiskThresholds = .default) async -> UsageSnapshot {
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
            // Session discovery (ps + lsof + transcript reads) runs concurrently with the network
            // rather than after it, so it no longer adds serially to the refresh time.
            async let usage = client.fetchUsage(token: creds.accessToken)
            async let profile = client.fetchProfile(token: creds.accessToken)
            async let sess = detectSessionsAsync()
            let (u, p, s) = try await (usage, profile, sess)
            return UsageSnapshot(
                capturedAt: timestamp,
                planLabel: p.planLabel,
                windows: windows(from: u, now: timestamp, thresholds: thresholds),
                sessions: s,
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

    private func windows(from usage: Usage, now: Date, thresholds: RiskThresholds) -> [UsageSnapshot.Window] {
        usage.displayWindows.compactMap { kind, w in
            // A window with no scheduled reset (resets_at: null — unused window) has nothing to
            // count down and no span to pace against, so skip it rather than fabricate a date.
            guard let resetsAt = w.resetsAt else { return nil }
            // Estimate when this window opened so risk can account for pacing
            // (smart coloring: absolute usage + projection), then map to a level
            // using the user's warning/critical thresholds (ADR-0013).
            let start = resetsAt.addingTimeInterval(-kind.duration)
            let level = RiskScorer.level(
                utilization: w.utilization, windowStart: start, resetsAt: resetsAt, now: now,
                thresholds: thresholds
            )
            let pace = PaceForecast.hoursToFull(
                utilization: w.utilization, windowStart: start, resetsAt: resetsAt, now: now
            )
            return UsageSnapshot.Window(
                kind: kind.rawValue,
                label: kind.label,
                utilization: w.utilization,
                resetsAt: resetsAt,
                riskHex: level.hex,
                riskLabel: level.label,
                riskLevel: level.rawValue,
                isOver: w.utilization >= 100,
                paceWarningHours: pace
            )
        }
    }

    /// `detectSessions()` off the cooperative pool so it can overlap the network `async let`s.
    private func detectSessionsAsync() async -> [UsageSnapshot.Session] {
        await Task.detached(priority: .utility) { detectSessions() }.value
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
