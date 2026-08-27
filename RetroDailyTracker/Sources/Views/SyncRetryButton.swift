import SwiftUI
import SwiftData

/// Retries a failed or pending spreadsheet sync for a single entry.
///
/// Renders nothing when the entry is already synced, so it can be placed
/// unconditionally next to a sync status badge.
///
/// Reports failures inline via an alert rather than the system notification the
/// automatic retry loop uses — a user who just pressed a button is already looking
/// at the window.
struct SyncRetryButton: View {

    let entry: WorkEntry

    /// Optional so previews and the form's non-syncing configuration can omit it.
    let spreadsheetService: SpreadsheetServiceProtocol?

    @Environment(\.modelContext) private var modelContext

    @State private var isRetrying = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false

    var body: some View {
        Group {
            if entry.syncStatus != .synced {
                Button(action: retry) {
                    HStack(spacing: 6) {
                        if isRetrying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRetrying ? "Retrying…" : "Retry Sync")
                    }
                }
                .disabled(isRetrying || spreadsheetService == nil)
                .help(
                    spreadsheetService == nil
                        ? "Connect a spreadsheet in Settings to enable syncing."
                        : "Try syncing this entry to your spreadsheet again."
                )
                .accessibilityLabel("Retry syncing this entry")
            }
        }
        .alert("Sync Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The entry could not be synced.")
        }
        .alert("Entry Synced", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This entry has been written to your spreadsheet.")
        }
    }

    // MARK: - Actions

    private func retry() {
        guard let spreadsheetService else { return }

        isRetrying = true
        errorMessage = nil

        Task {
            defer { isRetrying = false }

            do {
                try await spreadsheetService.retrySync(for: entry)
                persistStatusChange()
                showSuccess = true
            } catch {
                // The service has already marked the entry failed; persist that too
                // so the badge stays accurate across relaunches.
                persistStatusChange()
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// Saves the `syncStatus` change made by the service.
    private func persistStatusChange() {
        do {
            try modelContext.save()
        } catch {
            // A failed save leaves the in-memory status correct but not durable.
            // Surfacing this would bury the sync result, so it is logged instead.
            Logger.syncRetry.error("Could not persist sync status: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Logging

private extension Logger {
    static let syncRetry = Logger(subsystem: "com.retro.dailytracker", category: "SyncRetryButton")
}
