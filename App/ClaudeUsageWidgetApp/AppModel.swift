import SwiftUI
import WidgetKit
import ClaudeUsageKit

/// Drives the menu-bar app: periodically runs the live pipeline, publishes the
/// snapshot to the UI, persists it for the widget, and nudges WidgetKit to reload.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    /// Active dashboard layout (Classic / Compact / Focus).
    @Published var layout: DashboardLayout = .classic
    /// The floating Agent Watchers overlay controller (F1–F5).
    let overlay = OverlayController()

    private let service: UsageService
    private let store: SharedStore
    private let focus: TerminalFocus
    private let history: HistoryStore
    private let settingsStore: SettingsStore
    private var loop: Task<Void, Never>?

    /// User settings (theme / thresholds / notifications) — persisted on change.
    @Published var settings: AppSettings {
        didSet { settingsStore.save(settings) }
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

    /// Per-model token-volume breakdown (Opus/Sonnet/Haiku/Fable/기타) in the timeframe.
    var historyCastTotals: [TokenHistory.CastTotal] { TokenHistory.byCast(timeframeTokenEvents) }
    /// Daily token consumption split into per-model segments (the stacked bar chart).
    var historyDayStacks: [TokenHistory.DayStack] { TokenHistory.byDayCast(timeframeTokenEvents) }
    /// Active/cached/cache-hit + trend-vs-previous-period summary for the timeframe.
    var historySummary: TokenHistory.Summary {
        TokenHistory.summary(tokenEvents, timeframe: historyTimeframe, now: Date())
    }

    /// Daily token-consumption buckets for the History browser.
    var historyTokenBuckets: [TokenHistory.DayBucket] { TokenHistory.byDay(filteredTokenEvents) }
    /// Heaviest day / top project within the current History filter.
    var historyHeaviestDay: TokenHistory.DayBucket? { TokenHistory.heaviestDay(filteredTokenEvents) }
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
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: (self?.interval ?? 60) * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        var snap = await service.snapshot()
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
        await playChew()   // API 콜 = 한 입
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

    /// Parse all transcripts off the main actor (potentially many MB of JSONL).
    func loadTokenHistory() async {
        let events = await Task.detached(priority: .utility) { JSONLParser.allEvents() }.value
        tokenEvents = events
    }

    /// Estimated window-open time for a window kind (for pacing/equilibrium).
    func windowStart(forKind kind: String) -> Date? {
        guard let w = snapshot?.windows.first(where: { $0.kind == kind }),
              let k = UsageWindowKind(rawValue: kind) else { return nil }
        return w.resetsAt.addingTimeInterval(-k.duration)
    }

    /// The day with the most token consumption (Monitoring "peak day").
    var peakDay: TokenHistory.DayBucket? { TokenHistory.heaviestDay(tokenEvents) }
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
