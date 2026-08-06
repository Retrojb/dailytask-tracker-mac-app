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
}
