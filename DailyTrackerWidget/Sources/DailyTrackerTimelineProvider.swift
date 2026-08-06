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

    private var sharedModelContainer: ModelContainer? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.retro.dailytracker"
        ) else {
            return nil
        }

        let storeURL = containerURL.appendingPathComponent("default.store")
        let configuration = ModelConfiguration(url: storeURL)

        do {
            return try ModelContainer(for: WorkEntry.self, configurations: configuration)
        } catch {
            return nil
        }
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
