import Foundation
import SwiftData

@Model
final class SpreadsheetConfig {
    var provider: String
    var spreadsheetURL: String
    var sheetName: String?
    var lastSyncDate: Date?

    init(
        provider: String,
        spreadsheetURL: String,
        sheetName: String? = nil,
        lastSyncDate: Date? = nil
    ) {
        self.provider = provider
        self.spreadsheetURL = spreadsheetURL
        self.sheetName = sheetName
        self.lastSyncDate = lastSyncDate
    }
}
