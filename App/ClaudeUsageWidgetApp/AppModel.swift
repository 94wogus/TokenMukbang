import SwiftUI
import WidgetKit
import ClaudeUsageKit

/// Drives the menu-bar app: periodically runs the live pipeline, publishes the
/// snapshot to the UI, persists it for the widget, and nudges WidgetKit to reload.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false

    private let service: UsageService
    private let store: SharedStore
    private let focus: TerminalFocus
    private var loop: Task<Void, Never>?

    /// How often to re-poll usage (seconds).
    private let interval: UInt64 = 60

    init(
        service: UsageService = UsageService(),
        store: SharedStore = SharedStore(),
        focus: TerminalFocus = TerminalFocus()
    ) {
        self.service = service
        self.store = store
        self.focus = focus
        start()
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
        let snap = await service.snapshot()
        snapshot = snap
        try? store.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
        await playChew()   // API 콜 = 한 입
    }

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

    /// Face shown in the menu bar: a chew frame while chewing, else the resting
    /// face for the headline zone.
    var menuBarMascot: String { chewFrame ?? headlineZone.restingFace }

    /// Menu-bar string. Delegates composition (face + percent + fixed-width
    /// padding) to `ClaudeUsageKit` so the logic lives in one place (ADR-0001);
    /// the app only supplies the transient chew frame.
    var menuBarText: String {
        guard let w = snapshot?.headlineWindow else { return "( ﹃ )  —" }
        return MukbangFace.menuBarText(utilization: w.utilization, chewFrame: chewFrame)
    }

    var menuBarColor: Color {
        guard let w = snapshot?.headlineWindow else { return .secondary }
        return w.riskColor
    }

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
