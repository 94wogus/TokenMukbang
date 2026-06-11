import Foundation

public enum NotificationEvent: String, Sendable, CaseIterable {
    case escalation     // crossed a warning/critical threshold upward
    case recovery       // dropped back below warning (digested)
    case pacing         // newly on track to 완식 before reset
    case reset          // a window reset (new 상 차림)
    case extraCredit    // extra usage credits
    case tokenExpiry    // OAuth token expired
}

/// A notification the app should deliver. POV-correct 먹방 copy (ADR-0009).
public struct NotificationAlert: Sendable, Equatable {
    public let event: NotificationEvent
    public let surfaceKind: String?
    public let title: String
    public let body: String

    public init(event: NotificationEvent, surfaceKind: String?, title: String, body: String) {
        self.event = event
        self.surfaceKind = surfaceKind
        self.title = title
        self.body = body
    }
}

/// Decides which notifications to fire by comparing the previous and current
/// snapshot — edge-triggered, so it naturally debounces (one alert per transition).
/// Pure + dependency-free → fully unit-tested; the app handles delivery (E2).
public enum NotificationDecider {
    /// Whether a window kind's surface is enabled in settings.
    static func surfaceEnabled(_ kind: String, _ s: NotificationSettings) -> Bool {
        switch kind {
        case "five_hour": return s.fiveHour
        case "seven_day", "seven_day_opus": return s.sevenDay
        case "seven_day_sonnet": return s.sonnet
        default: return s.sevenDay
        }
    }

    public static func alerts(
        previous: UsageSnapshot?,
        current: UsageSnapshot,
        settings: NotificationSettings,
        thresholds: RiskThresholds
    ) -> [NotificationAlert] {
        var out: [NotificationAlert] = []

        // Token expiry (global) — fire on the transition into an expired error.
        if settings.tokenExpiry,
           let err = current.error, err.contains("expired") || err.contains("만료"),
           !(previous?.error.map { $0.contains("expired") || $0.contains("만료") } ?? false) {
            out.append(NotificationAlert(
                event: .tokenExpiry, surfaceKind: nil,
                title: "주방에 다시 다녀오세요", body: MukbangCopy.event(.backToKitchen)))
        }

        for cur in current.windows {
            guard surfaceEnabled(cur.kind, settings) else { continue }
            let prev = previous?.windows.first { $0.kind == cur.kind }
            let prevUtil = prev?.utilization ?? 0
            let label = cur.label

            // Escalation: crossed warning or critical threshold upward.
            if settings.escalation {
                if prevUtil < thresholds.critical, cur.utilization >= thresholds.critical {
                    out.append(NotificationAlert(event: .escalation, surfaceKind: cur.kind,
                        title: "\(label) 흡입 중", body: "\(Int(cur.utilization))% 완식 — 곧 배 터집니다"))
                } else if prevUtil < thresholds.warning, cur.utilization >= thresholds.warning {
                    out.append(NotificationAlert(event: .escalation, surfaceKind: cur.kind,
                        title: "\(label) 과식 주의", body: "\(Int(cur.utilization))% 완식"))
                }
            }

            // Recovery: dropped back below warning without a reset.
            if settings.recovery, prevUtil >= thresholds.warning, cur.utilization < thresholds.warning,
               cur.resetsAt == prev?.resetsAt {
                out.append(NotificationAlert(event: .recovery, surfaceKind: cur.kind,
                    title: "\(label) 소화 완료", body: "\(Int(cur.utilization))%로 여유가 생겼습니다"))
            }

            // Reset: a new window (reset time changed and usage dropped).
            if settings.reset, let prev, cur.resetsAt != prev.resetsAt, cur.utilization < prev.utilization {
                out.append(NotificationAlert(event: .reset, surfaceKind: cur.kind,
                    title: "새 상 차림", body: MukbangCopy.event(.freshTable)))
            }

            // Pacing: newly projected to 완식 before reset.
            if settings.pacing, cur.paceWarningHours != nil, prev?.paceWarningHours == nil,
               let h = cur.paceWarningHours {
                out.append(NotificationAlert(event: .pacing, surfaceKind: cur.kind,
                    title: "\(label) 페이스 경고", body: MukbangCopy.event(.paceWarning(hoursToFull: h))))
            }
        }

        // NOTE: `extraCredit` is a reserved surface for TokenEater parity. It fires
        // once a snapshot exposes extra-usage credit signals; the usage API's
        // `extra_usage` field is not yet decoded into `UsageSnapshot`, so no alert is
        // emitted today and the Settings toggle for it is disabled accordingly.

        return out
    }
}
