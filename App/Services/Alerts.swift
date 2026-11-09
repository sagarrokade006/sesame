import AppKit
import OSLog
@preconcurrency import UserNotifications

/// Notifications about what happened at the lock screen. Only posts when notifications are already allowed; Sesame
/// asks for that once when it starts.
enum Alerts {
    /// Posted when someone clicks one of these notifications, so the window can show Activity.
    static let opened = Notification.Name("SesameAlertOpened")
    private static let log = Logger(subsystem: "com.sagarrokade.sesame", category: "alerts")

    static func failedAttempts(_ count: Int) {
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "1 failed face unlock while you were away" : "\(count) failed face unlocks while you were away"
        content.body = "Someone else may have tried to unlock your Mac. No images are kept."
        post(content, id: "sesame.failed-attempts")
    }

    private static func post(_ content: UNMutableNotificationContent, id: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                log.notice("alert skipped: notifications not allowed")
                return
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                if let error { log.error("alert failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }
}
