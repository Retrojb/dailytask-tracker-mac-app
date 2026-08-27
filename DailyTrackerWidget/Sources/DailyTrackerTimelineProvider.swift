import WidgetKit
import SwiftUI
import SwiftData

struct DailyTrackerEntry: TimelineEntry {
    let date: Date
    let taskCount: Int
    let meetingCount: Int
    let hasNotes: Bool
    let recentTasks: [String]
}

struct DailyTrackerTimelineProvider: TimelineProvider {

    // MARK: - Shared SwiftData Container

    /// Container over the same store the app writes to.
    ///
    /// This previously pointed at `default.store` with a `WorkEntry`-only schema.
    /// The app writes `RetroDailyTracker.store`, so the widget was reading a
    /// different file and always rendered an empty entry. Both the filename and
    /// the schema now come from ``PersistenceConfiguration``.
    ///
    /// Returns `nil` rather than trapping so a failure here degrades to the empty
    /// timeline entry instead of crashing the widget extension.
    private var sharedModelContainer: ModelContainer? {
        try? PersistenceConfiguration.makeContainer()
    }

    // MARK: - TimelineProvider

    func placeholder(in context: Context) -> DailyTrackerEntry {
        DailyTrackerEntry(
            date: Date(),
            taskCount: 3,
            meetingCount: 2,
            hasNotes: true,
            recentTasks: ["Review pull requests", "Update documentation", "Team standup"]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyTrackerEntry) -> Void) {
        if context.isPreview {
            let entry = DailyTrackerEntry(
                date: Date(),
                taskCount: 3,
                meetingCount: 2,
                hasNotes: true,
                recentTasks: ["Review pull requests", "Update documentation", "Team standup"]
            )
            completion(entry)
            return
        }

        let entry = fetchTodayEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyTrackerEntry>) -> Void) {
        let entry = fetchTodayEntry()
        let reloadDate = Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(reloadDate))
        completion(timeline)
    }

    // MARK: - Data Fetching

    private func fetchTodayEntry() -> DailyTrackerEntry {
        guard let container = sharedModelContainer else {
            return DailyTrackerEntry(
                date: Date(),
                taskCount: 0,
                meetingCount: 0,
                hasNotes: false,
                recentTasks: []
            )
        }

        let context = ModelContext(container)
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        let predicate = #Predicate<WorkEntry> { entry in
            entry.date >= startOfDay && entry.date < endOfDay
        }

        var descriptor = FetchDescriptor<WorkEntry>(predicate: predicate)
        descriptor.fetchLimit = 1

        do {
            let entries = try context.fetch(descriptor)
            if let workEntry = entries.first {
                return DailyTrackerEntry(
                    date: now,
                    taskCount: workEntry.tasks.count,
                    meetingCount: workEntry.attendees.count,
                    hasNotes: !workEntry.notes.isEmpty,
                    recentTasks: Array(workEntry.tasks.prefix(3))
                )
            }
        } catch {
            // Fall through to empty entry
        }

        return DailyTrackerEntry(
            date: now,
            taskCount: 0,
            meetingCount: 0,
            hasNotes: false,
            recentTasks: []
        )
    }
}
