import Foundation
import UserNotifications
import os.log

/// Handles notification tap actions to open the Entry Form in the Companion App.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let logger = Logger(subsystem: "com.retro.dailytracker", category: "NotificationDelegate")

    /// Posted when the user taps a notification, signaling the app to present the Entry Form.
    static let openEntryFormNotification = Notification.Name("OpenEntryForm")

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        logger.info("User tapped notification: \(response.notification.request.identifier)")

        // Post a notification so the app UI can navigate to the Entry Form.
        await MainActor.run {
            NotificationCenter.default.post(name: Self.openEntryFormNotification, object: nil)
        }
    }

    /// Present notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
