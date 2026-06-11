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
    }

    /// Best-effort: focus the terminal window hosting this session.
    func focusSession(_ s: UsageSnapshot.Session) {
        let active = ActiveSession(pid: s.pid, tty: s.tty, cwd: s.cwd, contextFraction: s.contextFraction)
        focus.focus(active)
    }

    // MARK: - Menu-bar label helpers

    var menuBarText: String {
        guard let w = snapshot?.headlineWindow else { return "—" }
        return "\(w.label) \(Formatting.percent(w.utilization))"
    }

    var menuBarColor: Color {
        guard let w = snapshot?.headlineWindow else { return .secondary }
        return w.riskColor
    }
}
