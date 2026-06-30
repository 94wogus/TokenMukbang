import Foundation
import AppKit
import UserNotifications
import TokenMukbangKit

/// Delivers `NotificationAlert`s (decided in TokenMukbangKit, ADR-0009 voice) via
/// the system notification center (E2). Authorization is requested once at launch.
enum NotificationService {
    /// userInfo keys for the session-finished notification, so the tap handler can
    /// rebuild an `ActiveSession` and focus its terminal (ADR-0022).
    enum Key {
        static let pid = "tmk.pid"
        static let tty = "tmk.tty"
        static let cwd = "tmk.cwd"
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func deliver(_ alert: NotificationAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "tmk-\(alert.event.rawValue)-\(alert.surfaceKind ?? "global")",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// A Claude Code session finished its turn (ADR-0022). Carries the session
    /// identity in `userInfo` so tapping the banner focuses its terminal.
    static func deliverSessionFinished(_ session: UsageSnapshot.Session) {
        let content = UNMutableNotificationContent()
        content.title = "\(session.projectName) cleaned its plate"
        content.body = "Session finished — tap to jump back to the terminal."
        content.sound = .default
        content.userInfo = [
            Key.pid: Int(session.pid),
            Key.tty: session.tty ?? "",
            Key.cwd: session.cwd,
        ]
        let request = UNNotificationRequest(
            // Per-pid identifier: a session that finishes again replaces its own banner.
            identifier: "tmk-session-finished-\(session.pid)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Handles notification interactions. For a session-finished banner, a tap focuses
/// the hosting terminal — the same best-effort path as clicking a session row
/// (ADR-0008/ADR-0022). Also lets banners show while the app is foreground.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let focus = TerminalFocus()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let pid = info[NotificationService.Key.pid] as? Int {
            let ttyRaw = info[NotificationService.Key.tty] as? String ?? ""
            let tty = ttyRaw.isEmpty ? nil : ttyRaw
            let cwd = info[NotificationService.Key.cwd] as? String ?? ""
            let session = ActiveSession(pid: Int32(pid), tty: tty, cwd: cwd, contextFraction: nil)
            focus.focus(session)
        }
        completionHandler()
    }
}
