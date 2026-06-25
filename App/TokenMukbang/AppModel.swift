import SwiftUI
import WidgetKit
import TokenMukbangKit

/// Drives the menu-bar app: periodically runs the live pipeline, publishes the
/// snapshot to the UI, persists it for the widget, and nudges WidgetKit to reload.
@MainActor
final class AppModel: ObservableObject {
    /// The one live model shared by the AppKit status-item controller (which owns the normal glass
    /// window — ADR-0019) and the dev/screenshot SwiftUI scene.
    static let shared = AppModel()

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    /// Active window tab (Now / History / Settings).
    @Published var layout: DashboardLayout = .dashboard
    /// Active Settings sub-tab (Appearance / Alerts).
    @Published var settingsTab: SettingsTab = .appearance
    /// The floating Agent Watchers overlay controller (F1–F5).
    let overlay = OverlayController()

    private let service: UsageService
    private let store: SharedStore
    private let focus: TerminalFocus
    private let history: HistoryStore
    private let settingsStore: SettingsStore
    private var loop: Task<Void, Never>?
    /// Keeps the background poll loop alive. This is an `LSUIElement` accessory app, so when no
    /// window is open macOS App Nap throttles the `Task.sleep` loop to a near-halt — the symptom
    /// being usage that only refreshed on a manual click (user 2026-06-23). A held
    /// `.userInitiatedAllowingIdleSystemSleep` activity disables App Nap so polling keeps running
    /// while the Mac is awake, yet still lets the machine sleep when idle.
    private var pollActivity: NSObjectProtocol?

    // MARK: - Retrospective (ADR-0020 — "usage meter → reflection mirror")
    private let retroBuilder = RetrospectiveBuilder()
    private let retroStore = RetrospectiveStore()
    /// Yesterday's retrospective. The metadata layer (A) is built cheaply from local
    /// token events; the content layer (`topics`, B) is filled only on demand.
    @Published private(set) var retrospective: RetrospectiveSummary?
    /// True while the on-demand `claude` CLI summarization is running.
    @Published private(set) var isGeneratingRetro = false
    /// Whether the local `claude` CLI is installed — drives graceful degrade to A-only.
    let claudeAvailable: Bool = ClaudeCLISummarizer.resolvedPath() != nil

    /// API-equivalent value of this billing period's tokens vs the flat subscription — the
    /// Now-tab Value/Savings card (ADR-0021). Recomputed on token load + settings change, not
    /// per render (the event set is large; per-render scanning would be wasteful).
    @Published private(set) var valueEstimate: ValueEstimate?

    /// User settings (theme / thresholds / notifications) — persisted on change.
    @Published var settings: AppSettings {
        didSet {
            settingsStore.save(settings)
            recomputeValueEstimate()   // plan price / billing day / display zone feed the Value card
            if oldValue.thresholds != settings.thresholds {
                applyThresholdRecolor() // recolor menu bar + cards + widget now, not next poll (ADR-0013)
            }
        }
    }

    /// Persisted 7-day history (for sparklines / graph / browser).
    @Published private(set) var historySamples: [HistorySample] = []
    /// History-browser filter: which model to isolate (nil = all). Tapping a model
    /// breakdown bar sets this; tapping again clears it.
    @Published var historyModelFilter: ModelCast?
    /// History-browser timeframe (24h / 7d / 30d / 90d).
    @Published var historyTimeframe: Timeframe = .week

    /// Token events under the current History filter (timeframe + model) — single
    /// filtering seam reused by the buckets/heaviest/top computations.
    private var filteredTokenEvents: [TokenEvent] {
        HistoryFilter.tokenEvents(
            tokenEvents, timeframe: historyTimeframe, cast: historyModelFilter, now: Date()
        )
    }

    /// All token events in the timeframe (ignoring the model filter) — for the
    /// per-model breakdown, which must show *every* model side by side.
    private var timeframeTokenEvents: [TokenEvent] {
        HistoryFilter.tokenEvents(tokenEvents, timeframe: historyTimeframe, cast: nil, now: Date())
    }

    /// Calendar in the user's chosen display zone (Settings → General; nil = follow system).
    /// Day buckets and chart axes are computed in this zone so a "day" lines up with the user's
    /// wall clock rather than UTC. (Kit aggregations keep their UTC default for tests.)
    var displayCalendar: Calendar { settings.displayCalendar }

    /// Per-model token-volume breakdown (Opus/Sonnet/Haiku/Fable/기타) in the timeframe.
    var historyCastTotals: [TokenHistory.CastTotal] { TokenHistory.byCast(timeframeTokenEvents) }
    /// Daily token consumption split into per-model segments (the stacked bar chart).
    var historyDayStacks: [TokenHistory.DayStack] {
        TokenHistory.byDayCast(timeframeTokenEvents, calendar: displayCalendar)
    }
    /// Active/cached/cache-hit + trend-vs-previous-period summary for the timeframe.
    var historySummary: TokenHistory.Summary {
        TokenHistory.summary(tokenEvents, timeframe: historyTimeframe, now: Date())
    }

    /// Daily token-consumption buckets for the History browser.
    var historyTokenBuckets: [TokenHistory.DayBucket] {
        TokenHistory.byDay(filteredTokenEvents, calendar: displayCalendar)
    }
    /// Heaviest day / top project within the current History filter.
    var historyHeaviestDay: TokenHistory.DayBucket? {
        TokenHistory.heaviestDay(filteredTokenEvents, calendar: displayCalendar)
    }
    var historyTopProject: (project: String, tokens: Int)? { TokenHistory.topProject(filteredTokenEvents) }

    /// How often to re-poll the usage API (seconds). 5 min to stay well under
    /// the OAuth rate limit (60s was hitting 429s).
    private let interval: UInt64 = 300

    init(
        service: UsageService = UsageService(),
        store: SharedStore = SharedStore(),
        focus: TerminalFocus = TerminalFocus(),
        history: HistoryStore = HistoryStore(),
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.service = service
        self.store = store
        self.focus = focus
        self.history = history
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.historySamples = history.load()
        NotificationService.requestAuthorization()
        start()
        startCredentialWatch()
        Task { [weak self] in await self?.loadTokenHistory() }
    }

    /// Preview/render model: a fixed snapshot, no polling, no side effects — used by
    /// the headless ImageRenderer design-iteration path.
    init(previewSnapshot: UsageSnapshot, settings: AppSettings = .default, tokenEvents: [TokenEvent] = []) {
        self.service = UsageService()
        self.store = SharedStore()
        self.focus = TerminalFocus()
        self.history = HistoryStore()
        self.settingsStore = SettingsStore()
        self.settings = settings
        self.snapshot = previewSnapshot
        self.tokenEvents = tokenEvents
        // Build the Value estimate from the preview events so the render/snapshot harness
        // actually exercises the Value card (otherwise it always shows the empty state).
        recomputeValueEstimate()
    }

    /// Snapshot from the previous poll — for edge-triggered notifications.
    private var previousSnapshot: UsageSnapshot?

    /// Reactively refresh when Claude Code rewrites its credential file (H1).
    private var credentialWatcher: (any FileWatching)?
    private func startCredentialWatch() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/.credentials.json")
        credentialWatcher = FileWatcher(path: path) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        credentialWatcher?.start()
    }

    deinit {
        loop?.cancel()
        // `pollActivity` is intentionally not ended here: `AppModel.shared` lives for the whole
        // app lifetime, and a nonisolated deinit can't touch the non-Sendable activity token.
    }

    func start() {
        guard loop == nil else { return }
        // Opt out of App Nap for the lifetime of the loop (see `pollActivity`).
        pollActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Periodic Claude usage polling")
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                await self?.refreshTokenHistoryIncremental()   // keep Value/History live (B, cheap — ADR-0021)
                try? await Task.sleep(nanoseconds: (self?.interval ?? 60) * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        // The poll loop, the credential watcher, window-open and wake can all fire at once;
        // coalesce overlapping calls (MainActor serializes this guard before the first await).
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var snap = await service.snapshot(thresholds: settings.thresholds)
        history.record(snap)            // append to 7-day history
        historySamples = history.load()
        // Attach the headline sparkline so the widget can draw it offline.
        if let kind = snap.headlineWindow?.kind {
            snap.headlineSparkline = sparkline(forKind: kind, buckets: 24).map(\.value)
        }
        // Edge-triggered notifications (E1/E2): compare against the previous poll.
        let alerts = NotificationDecider.alerts(
            previous: previousSnapshot, current: snap,
            settings: settings.notifications, thresholds: settings.thresholds)
        for alert in alerts { NotificationService.deliver(alert) }
        previousSnapshot = snap

        snapshot = snap
        try? store.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
        // Cosmetic only — fire-and-forget so the UI updates and `isRefreshing` drops the moment
        // data lands, instead of staying "busy" for the whole chew animation. API 콜 = 한 입
        Task { [weak self] in await self?.playChew() }
    }

    /// Recolor the current snapshot's windows from the just-changed warning/critical
    /// thresholds without a network round-trip, then push it to the widget so the menu
    /// bar, popover cards and widget all recolor at once (ADR-0013). Utilization is
    /// unchanged, so notification baselines (`previousSnapshot`) need no update.
    private func applyThresholdRecolor() {
        guard let snap = snapshot else { return }
        let recolored = snap.recolored(thresholds: settings.thresholds)
        snapshot = recolored
        try? store.write(recolored)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sparkline series for a window kind over the retained history.
    func sparkline(forKind kind: String, buckets: Int = 28) -> [Sparkline.Point] {
        Sparkline.series(
            from: historySamples, windowKind: kind,
            span: HistoryStore.retention, buckets: buckets, now: Date()
        )
    }

    /// Window kinds matching the current history-browser model filter.
    var filteredHistoryKinds: [String] {
        HistoryFilter.windowKinds(for: historyModelFilter)
    }

    // MARK: - Token consumption history (ADR-0012)

    @Published private(set) var tokenEvents: [TokenEvent] = []
    /// True while the first transcript parse is running — lets cards show a "loading" state
    /// instead of vanishing (a heavy user's transcripts take a few seconds even cached).
    @Published private(set) var isLoadingTokens = false
    /// The last parse result, kept so the 5-min poll can do a cheap **incremental** update
    /// (re-parse only changed files) instead of a full disk-cache rebuild (ADR-0021 A/B refresh).
    private var eventSnapshot: EventCache.Snapshot?

    /// **(A) Full, authoritative reload** — disk-cache-backed full rebuild off the main actor
    /// (potentially >1GB of JSONL; `EventCache` re-parses only changed files). Used on launch and
    /// the manual ↻ refresh button — a full re-sync that also self-heals any incremental drift.
    func loadTokenHistory() async {
        if tokenEvents.isEmpty { isLoadingTokens = true }   // only show "loading" before we have anything
        let snap = await Task.detached(priority: .utility) { EventCache.load() }.value
        eventSnapshot = snap
        tokenEvents = snap.events
        isLoadingTokens = false
        loadRetrospective()
        recomputeValueEstimate()
    }

    /// **(B) Incremental refresh** — re-parse only the files that changed since the last snapshot
    /// (cheap, history-size-independent) and recompute the Value estimate. Driven by the 5-min poll
    /// so the Value/History numbers stay live mid-session without the full-cache I/O each tick.
    /// Falls back to a full `loadTokenHistory()` if there's no snapshot yet. Skips the (unchanged
    /// "yesterday") retrospective.
    func refreshTokenHistoryIncremental() async {
        guard let prev = eventSnapshot else { await loadTokenHistory(); return }
        let snap = await Task.detached(priority: .utility) { EventCache.update(previous: prev) }.value
        eventSnapshot = snap
        tokenEvents = snap.events
        recomputeValueEstimate()
    }

    /// Recompute the billing-period Value estimate from local token events (ADR-0021). Cheap
    /// aggregation in Kit; called on token load and whenever settings (plan price / billing day /
    /// display zone) change — never per SwiftUI render.
    func recomputeValueEstimate() {
        guard !tokenEvents.isEmpty else { valueEstimate = nil; return }
        let now = Date()
        let start = settings.billingPeriodStart(now: now, calendar: displayCalendar)
        valueEstimate = ValueEstimate.build(events: tokenEvents, periodStart: start, periodEnd: now)
    }

    /// Build yesterday's **metadata (A)** retrospective from local token events and merge
    /// any previously-generated **topics (B)** from the app-only cache. Cheap and
    /// token-free — safe to call on load/refresh. **Never** calls the `claude` CLI; that
    /// is `generateRetrospectiveTopics()` only (on-demand, 먹방 paradox — ADR-0020).
    func loadRetrospective() {
        // Bucket "yesterday" + hourly in the user's display zone (Settings → General) so the
        // retrospective's day boundary and "WHEN" hour match the rest of the app, not UTC.
        var summary = retroBuilder.yesterday(events: tokenEvents, now: Date(), calendar: displayCalendar)
        if let cached = retroStore.summary(for: summary.periodStart), let topics = cached.topics {
            summary.topics = topics   // reuse generated content; don't re-spend tokens
        }
        retrospective = summary
    }

    #if DEBUG
    /// Preview/render-only: inject generated topics so the Retro tab's post-generate state
    /// (summary + themes + Regenerate/Copy) is reviewable headlessly. Not used by the live app.
    func previewInjectTopics(_ topics: RetroTopics) { retrospective?.topics = topics }
    #endif

    /// **On-demand** content layer (B): send yesterday's conversation digest to the local
    /// `claude` CLI, attach the resulting topics, and cache them app-only. This is the ONLY
    /// path that spends tokens for the retrospective — it is never wired into the periodic poll
    /// (`refresh()`), honoring the 먹방 paradox (ADR-0020). Uses the CLI's own auth, never
    /// the OAuth token (ADR-0002); results never touch `SharedStore` (ADR-0003).
    func generateRetrospectiveTopics() async {
        guard !isGeneratingRetro, let base = retrospective,
              let claudePath = ClaudeCLISummarizer.resolvedPath() else { return }
        isGeneratingRetro = true
        defer { isGeneratingRetro = false }

        let start = base.periodStart, end = base.periodEnd
        let events = tokenEvents
        let plan = snapshot?.planLabel   // plan-aware coaching: frame cost as window-burn for subs
        let cal = displayCalendar        // capture on the main actor (settings is main-actor)
        let tz = settings.resolvedTimeZone
        // Coach input = usage-pattern metrics (the signal) + a small balanced prompt sample
        // (flavor). Built off the main actor (transcript walk can be heavy).
        let coachInput = await Task.detached(priority: .utility) { () -> String in
            let (byProject, order) = TranscriptDigest.collect(periodStart: start, periodEnd: end)
            let promptCounts = byProject.mapValues(\.count)
            let metrics = RetrospectiveMetrics.build(events: events, promptCounts: promptCounts,
                                                     periodStart: start, periodEnd: end, calendar: cal)
            // Keep the sample prompts to exactly the projects the coach tabulates, so it can't
            // cite a prompt-only project that's absent from the metrics/Menu (window-mismatch fix).
            let coached = Set(metrics.coachedProjects.map(\.project))
            let sample = TranscriptDigest.assemble(byProject: byProject, order: order,
                                                   maxChars: 4_000, limitTo: coached)
            return metrics.coachInputText(planLabel: plan, timeZone: tz) + (sample.isEmpty ? "" : "\n\nSample prompts:\n" + sample)
        }.value

        let summarizer = ClaudeCLISummarizer(runner: SystemProcessRunner(), claudePath: claudePath)
        guard let topics = await summarizer.summarize(digest: coachInput, now: Date()) else { return }

        var updated = base
        updated.topics = topics
        retrospective = updated
        retroStore.save(updated)   // app-only cache; widget never reads this
    }

    /// Estimated window-open time for a window kind (for pacing/equilibrium).
    func windowStart(forKind kind: String) -> Date? {
        guard let w = snapshot?.windows.first(where: { $0.kind == kind }),
              let k = UsageWindowKind(rawValue: kind) else { return nil }
        return w.resetsAt.addingTimeInterval(-k.duration)
    }

    /// The day with the most token consumption (Monitoring "peak day").
    var peakDay: TokenHistory.DayBucket? { TokenHistory.heaviestDay(tokenEvents, calendar: displayCalendar) }
    /// The project that ate the most tokens (History "top project").
    var topProject: (project: String, tokens: Int)? { TokenHistory.topProject(tokenEvents) }

    /// Best-effort: focus the terminal window hosting this session.
    func focusSession(_ s: UsageSnapshot.Session) {
        let active = ActiveSession(pid: s.pid, tty: s.tty, cwd: s.cwd, contextFraction: s.contextFraction)
        focus.focus(active)
    }

    // MARK: - Menu-bar label helpers

    /// The current chew animation frame, set transiently after each refresh
    /// ("API 콜 = 한 입"). nil when the mascot is resting.
    @Published private(set) var chewFrame: String?

    var headlineZone: MukbangZone {
        guard let w = snapshot?.headlineWindow else { return .cruising }
        return MukbangZone.forUtilization(w.utilization)
    }

    /// Windows to show in the menu bar as clean colored numbers (5h + 7d).
    var menuBarWindows: [UsageSnapshot.Window] {
        guard let windows = snapshot?.windows else { return [] }
        let wanted = ["five_hour", "seven_day"]
        let picked = windows.filter { wanted.contains($0.kind) }
        return picked.isEmpty ? Array(windows.prefix(2)) : picked
    }

    /// Face shown in the popover header: a chew frame while chewing, else the
    /// resting face for the headline zone. (The menu bar shows numbers, not the
    /// mascot — the mascot lives in the popover + widget.)
    var menuBarMascot: String { chewFrame ?? headlineZone.restingFace }

    /// One bite cycle through the headline zone's chew frames.
    private func playChew() async {
        let zone = headlineZone
        let interval = MukbangFace.chewInterval(for: zone)
        guard interval > 0 else { chewFrame = nil; return }
        for frame in MukbangFace.chewFrames(for: zone) {
            chewFrame = frame
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        chewFrame = nil
    }
}
