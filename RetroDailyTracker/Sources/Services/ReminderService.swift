import Foundation
import UserNotifications
import os.log

final class ReminderService: ReminderServiceProtocol {

    private let notificationCenter: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.retro.dailytracker", category: "ReminderService")

    /// Identifier prefix for weekday reminder notifications.
    private static let reminderIdentifierPrefix = "daily-reminder-weekday-"

    /// Identifier suffix for retry notifications.
    private static let retryIdentifierSuffix = "-retry"

    /// Maximum number of retry attempts for a failed notification.
    private static let maxRetryAttempts = 1

    /// Delay in seconds before retrying a failed notification delivery.
    private static let retryDelaySeconds: TimeInterval = 5 * 60

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - ReminderServiceProtocol

    func scheduleWeekdayReminders() async throws {
        try await requestAuthorizationIfNeeded()

        // Cancel existing reminders before rescheduling
        await cancelAllReminders()

        // Schedule notifications for the next 5 weekdays (Mon-Fri)
        // Weekday values: 2 = Monday, 3 = Tuesday, ..., 6 = Friday
        for weekday in 2...6 {
            let content = makeNotificationContent()
            let trigger = makeCalendarTrigger(weekday: weekday)
            let identifier = Self.reminderIdentifierPrefix + "\(weekday)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            try await notificationCenter.add(request)
            logger.info("Scheduled reminder for weekday \(weekday)")
        }
    }

    func cancelAllReminders() async {
        let identifiers = (2...6).map { Self.reminderIdentifierPrefix + "\($0)" }
        let retryIdentifiers = (2...6).map { Self.reminderIdentifierPrefix + "\($0)" + Self.retryIdentifierSuffix }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers + retryIdentifiers)
        logger.info("Cancelled all pending reminders")
    }

    func handleDeliveryFailure(for date: Date) async {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        let retryIdentifier = Self.reminderIdentifierPrefix + "\(weekday)" + Self.retryIdentifierSuffix

        // Check if a retry has already been attempted by looking for a pending retry request
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let hasExistingRetry = pendingRequests.contains { $0.identifier == retryIdentifier }

        if hasExistingRetry {
            // Retry already scheduled or exhausted — log and suppress until next weekday
            logger.error("Retry exhausted for weekday \(weekday) on \(date). Suppressing until next scheduled weekday.")
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [retryIdentifier])
            return
        }

        // Schedule a one-time retry within 5 minutes
        let content = makeNotificationContent()
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.retryDelaySeconds,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: retryIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            logger.info("Scheduled retry notification for weekday \(weekday) in \(Self.retryDelaySeconds) seconds")
        } catch {
            logger.error("Failed to schedule retry notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Requests notification authorization if not already granted.
    private func requestAuthorizationIfNeeded() async throws {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                logger.warning("User denied notification authorization")
            }
        case .denied:
            logger.warning("Notification authorization denied by user")
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }
    }

    /// Creates the notification content with a personalized greeting.
    private func makeNotificationContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Daily Work Reminder"
        content.body = "Hey \(personalizedName()), time to log what you accomplished today!"
        content.sound = .default
        return content
    }

    /// Creates a calendar trigger for a specific weekday at 3:00 PM Eastern Time.
    private func makeCalendarTrigger(weekday: Int) -> UNCalendarNotificationTrigger {
        var dateComponents = DateComponents()
        dateComponents.hour = 15
        dateComponents.minute = 0
        dateComponents.weekday = weekday
        dateComponents.timeZone = TimeZone(identifier: "America/New_York")

        return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
    }

    /// Extracts the user's first name for personalization.
    ///
    /// Uses `NSFullUserName()`, splits on whitespace, and takes the first component.
    /// Falls back to "there" if the full name is empty or unavailable.
    static func extractFirstName(from fullName: String) -> String {
        let components = fullName.split(separator: " ", omittingEmptySubsequences: true)
        guard let firstName = components.first, !firstName.isEmpty else {
            return "there"
        }
        return String(firstName)
    }

    /// Returns the personalized name to use in notification body.
    private func personalizedName() -> String {
        let fullName = NSFullUserName()
        return Self.extractFirstName(from: fullName)
    }
}
