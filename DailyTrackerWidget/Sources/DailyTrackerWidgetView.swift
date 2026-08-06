import SwiftUI
import WidgetKit

// MARK: - Animal Image Loader

/// Loads a cached animal image from the App Group container, if available.
struct AnimalImageLoader {
    static func loadCachedImage() -> Data? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.retro.dailytracker"
        ) else {
            return nil
        }

        let imageFileURL = containerURL.appendingPathComponent("animal_image.data")
        return try? Data(contentsOf: imageFileURL)
    }
}

// MARK: - Small Widget View

struct DailyTrackerWidgetSmallView: View {
    let entry: DailyTrackerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)

            if entry.taskCount == 0 && entry.meetingCount == 0 && !entry.hasNotes {
                Spacer()
                Text("No entries logged today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                HStack(spacing: 12) {
                    Label("\(entry.taskCount)", systemImage: "checkmark.circle")
                    Label("\(entry.meetingCount)", systemImage: "person.2")
                }
                .font(.caption)

                Spacer()
            }

            // Show cached animal image if available
            if let imageData = AnimalImageLoader.loadCachedImage(),
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack(spacing: 8) {
                Button(intent: AddNoteIntent()) {
                    Label("Note", systemImage: "plus.circle")
                        .font(.caption2)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Button(intent: FetchAnimalIntent()) {
                    Label("Animal", systemImage: "pawprint")
                        .font(.caption2)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

// MARK: - Medium Widget View

struct DailyTrackerWidgetMediumView: View {
    let entry: DailyTrackerEntry

    var body: some View {
        HStack(spacing: 0) {
            DailyTrackerWidgetSmallView(entry: entry)
                .frame(maxWidth: .infinity)

            if !entry.recentTasks.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.recentTasks.prefix(3), id: \.self) { task in
                        Text(truncatedTask(task))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func truncatedTask(_ task: String) -> String {
        if task.count > 40 {
            return String(task.prefix(40)) + "…"
        }
        return task
    }
}

// MARK: - Adaptive Widget View

struct DailyTrackerWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DailyTrackerEntry

    var body: some View {
        switch family {
        case .systemSmall:
            DailyTrackerWidgetSmallView(entry: entry)
        case .systemMedium:
            DailyTrackerWidgetMediumView(entry: entry)
        default:
            DailyTrackerWidgetSmallView(entry: entry)
        }
    }
}
