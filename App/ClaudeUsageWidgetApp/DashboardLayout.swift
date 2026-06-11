import Foundation

/// The three popover/dashboard layouts (TokenEater parity).
public enum DashboardLayout: String, CaseIterable, Identifiable, Sendable {
    case classic   // windows + sessions, full detail
    case compact   // condensed windows + session count
    case focus     // only the headline window, large + sparkline
    case history   // 7-day history browser (filter by model)
    case settings  // theme / thresholds / notifications

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .classic: return "Classic"
        case .compact: return "Compact"
        case .focus: return "Focus"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }
}
