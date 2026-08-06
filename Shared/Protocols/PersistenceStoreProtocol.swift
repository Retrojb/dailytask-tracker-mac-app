import Foundation

protocol PersistenceStoreProtocol {
    func save(entry: WorkEntry) throws
    func fetchEntry(for date: Date) -> WorkEntry?
    func fetchAllEntries() -> [WorkEntry]
    func appendToEntry(date: Date, tasks: [String], attendees: [String], notes: [String]) throws
    func purgeExpiredEntries(retentionDays: Int) throws
}
