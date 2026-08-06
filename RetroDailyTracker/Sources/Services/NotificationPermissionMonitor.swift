import Foundation
import UserNotifications
import os.log

/// Monitors the notification authorization status and exposes it as observable state.
@Observable
final class NotificationPermissionMonitor {

    /// Shared instance for use across the app.
    static let shared = NotificationPermissionMonitor()

    /// Whether the user has denied notification permission.
    private(set) var isDenied: Bool = false

    private let logger = Logger(subsystem: "com.retro.dailytracker", category: "NotificationPermissionMonitor")

    private init() {}

    /// Checks the current notification authorization status and updates `isDenied`.
    @MainActor
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .denied:
            isDenied = true
            logger.info("Notification permission is denied")
        case .authorized, .provisional, .ephemeral:
            isDenied = false
            logger.info("Notification permission is granted")
        case .notDetermined:
            isDenied = false
            logger.info("Notification permission not yet determined")
        @unknown default:
            isDenied = false
        }
    }
}
