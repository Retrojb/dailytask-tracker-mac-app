import Foundation

enum SpreadsheetProvider {
    case googleSheets
    case microsoftExcel
}

protocol SpreadsheetServiceProtocol {
    func configure(provider: SpreadsheetProvider, spreadsheetURL: URL) async throws
    func authenticate() async throws
    func writeEntry(_ entry: WorkEntry) async throws
    func updateEntry(_ entry: WorkEntry) async throws
    func retryPendingSync() async

    /// Performs a single user-initiated sync attempt for one entry.
    ///
    /// Distinct from the automatic retry loop in two ways: it makes exactly one
    /// attempt rather than consuming the entry's retry budget, and it throws on
    /// failure so the caller can show the reason inline instead of relying on a
    /// system notification.
    ///
    /// Updates `entry.syncStatus`; the caller is responsible for saving its
    /// `ModelContext`.
    func retrySync(for entry: WorkEntry) async throws
}
