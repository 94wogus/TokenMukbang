import Foundation

/// A self-contained, Codable view of everything the UI shows at a moment in time.
/// The app writes this to a shared container; the WidgetKit extension reads it
/// (the widget never touches Keychain or the network itself).
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public let kind: String          // UsageWindowKind.rawValue
        public let label: String
        public let utilization: Double
        public let resetsAt: Date
        public let riskHex: String
        public let riskLabel: String
        /// RiskLevel.rawValue (calm/watch/warning/critical) — the app resolves a
        /// scheme-branched color from this (Kit stays UI-free / color-free).
        public let riskLevel: String
        /// True when utilization has reached/passed 100% (a categorically distinct
        /// "over" state that gets a non-color cue, not just a hotter hue).
        public let isOver: Bool
        /// Hours until this window hits 100% at the current pace, if it will
        /// before reset — drives the "이 속도면 N시간 뒤 완식" warning. nil = safe pace.
        public let paceWarningHours: Int?

        public init(kind: String, label: String, utilization: Double, resetsAt: Date, riskHex: String, riskLabel: String, riskLevel: String = "calm", isOver: Bool = false, paceWarningHours: Int? = nil) {
            self.kind = kind
            self.label = label
            self.utilization = utilization
            self.resetsAt = resetsAt
            self.riskHex = riskHex
            self.riskLabel = riskLabel
            self.riskLevel = riskLevel
            self.isOver = isOver
            self.paceWarningHours = paceWarningHours
        }
    }

    public struct Session: Codable, Sendable, Equatable, Identifiable {
        public let pid: Int32
        public let projectName: String
        public let cwd: String
        public let tty: String?
        public let contextFraction: Double?

        public var id: Int32 { pid }

        public init(pid: Int32, projectName: String, cwd: String, tty: String?, contextFraction: Double?) {
            self.pid = pid
            self.projectName = projectName
            self.cwd = cwd
            self.tty = tty
            self.contextFraction = contextFraction
        }
    }

    public let capturedAt: Date
    public let planLabel: String?
    public let windows: [Window]
    public let sessions: [Session]
    /// Set when the pipeline could not produce live data (expired token, offline…).
    public let error: String?
    /// Headline window's 7-day sparkline values (0...100), attached by the app
    /// before caching so the widget can draw it without history access.
    public var headlineSparkline: [Double]?

    public init(capturedAt: Date, planLabel: String?, windows: [Window], sessions: [Session], error: String?) {
        self.capturedAt = capturedAt
        self.planLabel = planLabel
        self.windows = windows
        self.sessions = sessions
        self.error = error
    }

    public static func failure(_ message: String, at date: Date) -> UsageSnapshot {
        UsageSnapshot(capturedAt: date, planLabel: nil, windows: [], sessions: [], error: message)
    }

    /// The window that should drive the menu-bar / widget headline (highest util).
    public var headlineWindow: Window? {
        windows.max { $0.utilization < $1.utilization }
    }
}
