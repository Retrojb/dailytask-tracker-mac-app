import Foundation

protocol ReminderServiceProtocol {
    func scheduleWeekdayReminders() async throws
    func cancelAllReminders() async
    func handleDeliveryFailure(for date: Date) async
}
