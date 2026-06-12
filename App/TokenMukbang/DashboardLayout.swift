import Foundation

/// The popover's two content modes, swapped by a TOP segmented toggle (현황 | 기록).
/// Settings is NOT a mode here — it opens a separate macOS Settings window (⌘,) via the
/// header gear, per native menu-bar conventions (research 2026-06-12: native popovers don't
/// use tab bars; config lives in a Settings window, a secondary analytical view is a top
/// segmented control or its own window — Apple HIG, Stats, iStat Menus, Itsycal).
public enum DashboardLayout: String, CaseIterable, Identifiable, Sendable {
    case dashboard // 현황 — hero window + secondary windows + sessions (the glance)
    case history   // 기록 — 7-day token history (filter by model)

    public var id: String { rawValue }

    /// Korean toggle labels (먹방 voice) — 현황(now) / 기록(history).
    public var label: String {
        switch self {
        case .dashboard: return "현황"
        case .history: return "기록"
        }
    }
}
