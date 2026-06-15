import Foundation

/// The main window's content modes, swapped by a TOP segmented toggle (Now | History | Settings).
/// Since 2026-06-15 the app is a single **normal glass window** (ADR-0019, supersedes ADR-0018's
/// borderless NSPanel popover) — so Settings is now an in-window tab, not a separate window.
public enum DashboardLayout: String, CaseIterable, Identifiable, Sendable {
    case dashboard // Now — hero window + secondary windows + sessions (the glance)
    case history   // History — 7-day token history (filter by model)
    case settings  // Settings — Appearance / Alerts (was a separate window)

    public var id: String { rawValue }

    /// Toggle labels — Now (the live glance) / History (7-day tokens) / Settings.
    public var label: String {
        switch self {
        case .dashboard: return "Now"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }
}
