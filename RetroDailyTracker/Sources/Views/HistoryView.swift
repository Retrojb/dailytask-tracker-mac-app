import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkEntry.date, order: .reverse) private var entries: [WorkEntry]

    var body: some View {
        List(entries) { entry in
            NavigationLink(destination: HistoryDetailView(entry: entry)) {
                HistoryRowView(entry: entry)
            }
        }
        .navigationTitle("History")
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Past work entries will appear here.")
                )
            }
        }
    }
}

// MARK: - Row View

private struct HistoryRowView: View {
    let entry: WorkEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(entry.tasks.count)", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label("\(entry.attendees.count)", systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            SyncStatusBadge(status: entry.syncStatus)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sync Status Badge

private struct SyncStatusBadge: View {
    let status: SyncStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch status {
        case .synced:
            return "checkmark.icloud"
        case .pending:
            return "arrow.clockwise.icloud"
        case .retrying:
            return "arrow.clockwise.icloud"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    private var iconColor: Color {
        switch status {
        case .synced:
            return .green
        case .pending:
            return .orange
        case .retrying:
            return .orange
        case .failed:
            return .red
        }
    }

    private var label: String {
        switch status {
        case .synced:
            return "Synced"
        case .pending:
            return "Pending"
        case .retrying:
            return "Retrying"
        case .failed:
            return "Failed"
        }
    }
}

// MARK: - Detail View

struct HistoryDetailView: View {
    let entry: WorkEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text(entry.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    SyncStatusBadge(status: entry.syncStatus)
                }

                Divider()

                // Tasks Section
                if !entry.tasks.isEmpty {
                    DetailSection(title: "Tasks", systemImage: "checkmark.circle") {
                        ForEach(entry.tasks, id: \.self) { task in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                                Text(task)
                            }
                        }
                    }
                }

                // Attendees Section
                if !entry.attendees.isEmpty {
                    DetailSection(title: "Attendees", systemImage: "person.2") {
                        ForEach(entry.attendees, id: \.self) { attendee in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "person")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(attendee)
                            }
                        }
                    }
                }

                // Notes Section
                if !entry.notes.isEmpty {
                    DetailSection(title: "Notes", systemImage: "note.text") {
                        ForEach(entry.notes, id: \.self) { note in
                            Text(note)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Entry Details")
        .frame(minWidth: 400)
    }
}

// MARK: - Detail Section Helper

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
    }
}

// MARK: - Previews

#Preview("History View") {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: WorkEntry.self, inMemory: true)
}

#Preview("Detail View") {
    NavigationStack {
        HistoryDetailView(entry: WorkEntry(
            date: Date(),
            tasks: ["Reviewed PR #42", "Fixed login bug", "Updated documentation"],
            attendees: ["Alice", "Bob", "Charlie"],
            notes: ["Sprint planning went well", "Need to follow up on API changes"],
            syncStatus: .synced
        ))
    }
}
