import Foundation
import UserNotifications
import ClaudeUsageKit

/// Delivers `NotificationAlert`s (decided in ClaudeUsageKit, ADR-0009 voice) via
/// the system notification center (E2). Authorization is requested once at launch.
enum NotificationService {
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
}
