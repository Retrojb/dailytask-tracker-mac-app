import Foundation
import SwiftData

final class PersistenceStore: PersistenceStoreProtocol {

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init() {
        let schema = Schema([WorkEntry.self])
        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.retro.dailytracker"
        )

        let configuration: ModelConfiguration
        if let appGroupURL {
            let storeURL = appGroupURL.appendingPathComponent("RetroDailyTracker.store")
            configuration = ModelConfiguration(
                "RetroDailyTracker",
                schema: schema,
                url: storeURL
            )
        } else {
            // Fallback to default location if App Group container is inaccessible
            configuration = ModelConfiguration(
                "RetroDailyTracker",
                schema: schema
            )
        }

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }

        modelContext = ModelContext(modelContainer)
    }

    // MARK: - PersistenceStoreProtocol

    func save(entry: WorkEntry) throws {
        entry.updatedAt = Date()
        modelContext.insert(entry)
        try modelContext.save()
    }

    func fetchEntry(for date: Date) -> WorkEntry? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let predicate = #Predicate<WorkEntry> { entry in
            entry.date >= startOfDay && entry.date < endOfDay
        }

        var descriptor = FetchDescriptor<WorkEntry>(predicate: predicate)
        descriptor.fetchLimit = 1

        let results = (try? modelContext.fetch(descriptor)) ?? []
        return results.first
    }

    func fetchAllEntries() -> [WorkEntry] {
        var descriptor = FetchDescriptor<WorkEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.includePendingChanges = true

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func appendToEntry(date: Date, tasks: [String], attendees: [String], notes: [String]) throws {
        if let existing = fetchEntry(for: date) {
            existing.tasks.append(contentsOf: tasks)
            existing.attendees.append(contentsOf: attendees)
            existing.notes.append(contentsOf: notes)
            existing.updatedAt = Date()
            try modelContext.save()
        } else {
            let newEntry = WorkEntry(
                date: date,
                tasks: tasks,
                attendees: attendees,
                notes: notes
            )
            try save(entry: newEntry)
        }
    }

    func purgeExpiredEntries(retentionDays: Int) throws {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: Date())) else {
            return
        }

        let predicate = #Predicate<WorkEntry> { entry in
            entry.createdAt < cutoffDate
        }

        let descriptor = FetchDescriptor<WorkEntry>(predicate: predicate)
        let expiredEntries = (try? modelContext.fetch(descriptor)) ?? []

        for entry in expiredEntries {
            modelContext.delete(entry)
        }

        try modelContext.save()
    }
}
