import SwiftUI
import SwiftData
import UserNotifications
import os.log

@main
struct RetroDailyTrackerApp: App {

    /// Retained delegate instance so UNUserNotificationCenter keeps a strong reference.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Tracks the currently selected tab for deep link / notification navigation.
    @State private var selectedTab: AppTab = .entryForm

    /// Shared ModelContainer configured with the App Group container.
    private let modelContainer: ModelContainer

    /// Shared SpreadsheetService for syncing entries.
    private let spreadsheetService: SpreadsheetService

    /// Shared PersistenceStore for accessing entries.
    private let persistenceStore: PersistenceStore

    init() {
        // Schema and store URL are defined once in PersistenceConfiguration so the
        // app, the widget, and PersistenceStore cannot drift apart.
        self.modelContainer = PersistenceConfiguration.shared
        self.spreadsheetService = SpreadsheetService()
        self.persistenceStore = PersistenceStore(container: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                selectedTab: $selectedTab,
                spreadsheetService: spreadsheetService,
                persistenceStore: persistenceStore
            )
                .onReceive(NotificationCenter.default.publisher(for: NotificationDelegate.openEntryFormNotification)) { _ in
                    selectedTab = .entryForm
                    // Bring the app window to the front
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
                    await startRetrySyncTimer()
                }
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        // Handle com.retro.dailytracker://entry deep link
        guard url.scheme == "com.retro.dailytracker" else { return }

        switch url.host {
        case "entry":
            selectedTab = .entryForm
        default:
            break
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Retry Sync Timer

    /// Starts a background loop that retries pending sync operations every 5 minutes.
    private func startRetrySyncTimer() async {
        let logger = Logger(subsystem: "com.retro.dailytracker", category: "SyncRetry")

        while !Task.isCancelled {
            // Retry pending/retrying entries
            let entries = persistenceStore.fetchAllEntries()
            let pendingEntries = entries.filter { $0.syncStatus == .pending || $0.syncStatus == .retrying }

            if !pendingEntries.isEmpty {
                logger.info("Retrying sync for \(pendingEntries.count) pending entries")
                for entry in pendingEntries {
                    _ = await spreadsheetService.syncEntryWithRetry(
                        entry,
                        isUpdate: SpreadsheetService.isUpdate(entry)
                    )
                }
            }

            // Wait 5 minutes before next retry cycle
            try? await Task.sleep(for: .seconds(300))
        }
    }
}

// MARK: - App Tab

enum AppTab: String, CaseIterable, Identifiable {
    case entryForm
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entryForm: return "Entry"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .entryForm: return "square.and.pencil"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gear"
        }
    }
}

// MARK: - AppDelegate

/// AppDelegate registers the notification delegate early in the app lifecycle
/// and schedules weekday reminders.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Strong reference to the notification delegate to keep it alive.
    private let notificationDelegate = NotificationDelegate()

    private let reminderService = ReminderService()

    /// Logger for app lifecycle events.
    private let logger = Logger(subsystem: "com.retro.dailytracker", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationDelegate

        // Purge expired entries on launch (90-day retention policy)
        purgeExpiredData()

        // Schedule weekday reminders and check notification permission status
        Task {
            do {
                try await reminderService.scheduleWeekdayReminders()
            } catch {
                // Authorization may have been denied — check and update the monitor
            }
            await NotificationPermissionMonitor.shared.checkAuthorizationStatus()
        }
    }

    // MARK: - Data Retention

    /// Purges work entries older than 90 days on each app launch.
    private func purgeExpiredData() {
        // Uses the shared container, so this runs against the same store and
        // schema as the rest of the app.
        let store = PersistenceStore()
        do {
            try store.purgeExpiredEntries(retentionDays: 90)
            logger.info("Data retention purge completed successfully.")
        } catch {
            logger.error("Data retention purge failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
