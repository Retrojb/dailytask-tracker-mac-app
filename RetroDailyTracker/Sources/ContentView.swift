import SwiftUI

struct ContentView: View {

    @Binding var selectedTab: AppTab

    /// Shared SpreadsheetService instance for syncing entries.
    private let spreadsheetService: SpreadsheetServiceProtocol

    /// Shared persistence store, held rather than constructed in `body` so that a
    /// re-render does not build a new store on every pass.
    private let persistenceStore: PersistenceStoreProtocol

    /// Observable monitor for notification permission state.
    private var permissionMonitor = NotificationPermissionMonitor.shared

    init(
        selectedTab: Binding<AppTab>,
        spreadsheetService: SpreadsheetServiceProtocol = SpreadsheetService(),
        persistenceStore: PersistenceStoreProtocol = PersistenceStore()
    ) {
        self._selectedTab = selectedTab
        self.spreadsheetService = spreadsheetService
        self.persistenceStore = persistenceStore
    }

    var body: some View {
        VStack(spacing: 0) {
            // Notification permission denied banner
            if permissionMonitor.isDenied {
                NotificationPermissionBanner()
            }

            TabView(selection: $selectedTab) {
                // Entry Form Tab
                NavigationStack {
                    EntryFormView(persistenceStore: persistenceStore, spreadsheetService: spreadsheetService)
                }
                .tabItem {
                    Label(AppTab.entryForm.title, systemImage: AppTab.entryForm.systemImage)
                }
                .tag(AppTab.entryForm)

                // History Tab
                NavigationStack {
                    HistoryView()
                }
                .tabItem {
                    Label(AppTab.history.title, systemImage: AppTab.history.systemImage)
                }
                .tag(AppTab.history)

                // Settings Tab
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .task {
            // Re-check permission status when the view appears (e.g., user returns from Settings)
            await permissionMonitor.checkAuthorizationStatus()
        }
    }
}

// MARK: - Notification Permission Banner

/// A banner displayed when the user has denied notification permissions.
/// Provides a button to open System Settings for Notifications.
struct NotificationPermissionBanner: View {

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.white)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications Disabled")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Daily reminders require notification permission to work.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()

            Button("Open Settings") {
                openNotificationSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange)
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ContentView(selectedTab: .constant(.entryForm))
        .modelContainer(for: [WorkEntry.self, SpreadsheetConfig.self], inMemory: true)
}
