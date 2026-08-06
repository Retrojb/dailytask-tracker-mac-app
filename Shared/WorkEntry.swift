import Foundation
import SwiftData

@Model
final class WorkEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var tasks: [String]
    var attendees: [String]
    var notes: [String]
    var createdAt: Date
    var updatedAt: Date
    var syncStatusRaw: String

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date,
        tasks: [String] = [],
        attendees: [String] = [],
        notes: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.date = date
        self.tasks = tasks
        self.attendees = attendees
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatusRaw = syncStatus.rawValue
    }
}

enum SyncStatus: String, Codable {
    case pending
    case synced
    case failed
    case retrying
}
