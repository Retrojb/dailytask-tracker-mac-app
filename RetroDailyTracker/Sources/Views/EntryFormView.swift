import SwiftUI
import SwiftData

struct EntryFormView: View {

    // MARK: - Dependencies

    private let persistenceStore: PersistenceStoreProtocol
    private let spreadsheetService: SpreadsheetServiceProtocol?

    // MARK: - Form State

    @State private var tasks: [String] = [""]
    @State private var attendees: [String] = [""]
    @State private var notes: String = ""

    // MARK: - Feedback State

    @State private var validationErrors: [String] = []
    @State private var showConfirmation: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // MARK: - Init

    init(persistenceStore: PersistenceStoreProtocol, spreadsheetService: SpreadsheetServiceProtocol? = nil) {
        self.persistenceStore = persistenceStore
        self.spreadsheetService = spreadsheetService
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                tasksSection
                attendeesSection
                notesSection
                validationSection
                submitSection
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 400)
        .alert("Entry Saved", isPresented: $showConfirmation) {
            Button("OK") { resetForm() }
        } message: {
            Text("Your work entry has been saved successfully.")
        }
        .alert("Save Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Work Entry")
                .font(.title2)
                .fontWeight(.semibold)
            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Completed Tasks")
                    .font(.headline)
                Spacer()
                Text("\(nonEmptyTasks.count)/\(WorkEntryValidator.maxTasks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(tasks.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField("Task \(index + 1)", text: $tasks[index])
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: tasks[index]) { _, newValue in
                            if newValue.count > WorkEntryValidator.maxTaskLength {
                                tasks[index] = String(newValue.prefix(WorkEntryValidator.maxTaskLength))
                            }
                        }

                    Text("\(tasks[index].count)/\(WorkEntryValidator.maxTaskLength)")
                        .font(.caption2)
                        .foregroundStyle(
                            tasks[index].count > WorkEntryValidator.maxTaskLength - 50
                                ? .orange : .secondary
                        )
                        .frame(width: 60, alignment: .trailing)

                    if tasks.count > 1 {
                        Button(action: { removeTask(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove task \(index + 1)")
                    }
                }
            }

            if tasks.count < WorkEntryValidator.maxTasks {
                Button(action: addTask) {
                    Label("Add Task", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityLabel("Add another task")
            } else {
                Text("Maximum of \(WorkEntryValidator.maxTasks) tasks reached.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Attendees Section

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Meeting Attendees")
                    .font(.headline)
                Spacer()
                Text("\(nonEmptyAttendees.count)/\(WorkEntryValidator.maxAttendees)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(attendees.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField("Attendee \(index + 1)", text: $attendees[index])
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: attendees[index]) { _, newValue in
                            if newValue.count > WorkEntryValidator.maxAttendeeNameLength {
                                attendees[index] = String(newValue.prefix(WorkEntryValidator.maxAttendeeNameLength))
                            }
                        }

                    Text("\(attendees[index].count)/\(WorkEntryValidator.maxAttendeeNameLength)")
                        .font(.caption2)
                        .foregroundStyle(
                            attendees[index].count > WorkEntryValidator.maxAttendeeNameLength - 20
                                ? .orange : .secondary
                        )
                        .frame(width: 60, alignment: .trailing)

                    if attendees.count > 1 {
                        Button(action: { removeAttendee(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove attendee \(index + 1)")
                    }
                }
            }

            if attendees.count < WorkEntryValidator.maxAttendees {
                Button(action: addAttendee) {
                    Label("Add Attendee", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityLabel("Add another attendee")
            } else {
                Text("Maximum of \(WorkEntryValidator.maxAttendees) attendees reached.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Additional Notes")
                    .font(.headline)
                Spacer()
                Text("\(notes.count)/500")
                    .font(.caption)
                    .foregroundStyle(notes.count > 450 ? .orange : .secondary)
            }

            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: notes) { _, newValue in
                    if newValue.count > 500 {
                        notes = String(newValue.prefix(500))
                    }
                }
                .accessibilityLabel("Additional notes")
        }
    }

    // MARK: - Validation Feedback

    private var validationSection: some View {
        Group {
            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationErrors, id: \.self) { error in
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.08))
                )
            }
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        HStack {
            Spacer()
            Button("Submit Entry") {
                submitEntry()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Submit work entry")
        }
    }

    // MARK: - Actions

    private func addTask() {
        guard tasks.count < WorkEntryValidator.maxTasks else { return }
        tasks.append("")
    }

    private func removeTask(at index: Int) {
        guard tasks.count > 1 else { return }
        tasks.remove(at: index)
    }

    private func addAttendee() {
        guard attendees.count < WorkEntryValidator.maxAttendees else { return }
        attendees.append("")
    }

    private func removeAttendee(at index: Int) {
        guard attendees.count > 1 else { return }
        attendees.remove(at: index)
    }

    private func submitEntry() {
        validationErrors = []

        let filteredTasks = nonEmptyTasks
        let filteredAttendees = nonEmptyAttendees
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate submission - at least one task or one attendee required
        let submissionResult = WorkEntryValidator.validateSubmission(
            tasks: filteredTasks, attendees: filteredAttendees
        )
        if case .failure(let error) = submissionResult {
            validationErrors.append(error.description)
        }

        // Validate task constraints
        let taskResult = WorkEntryValidator.validateTaskConstraints(tasks: filteredTasks)
        if case .failure(let error) = taskResult {
            validationErrors.append(error.description)
        }

        // Validate attendee constraints
        let attendeeResult = WorkEntryValidator.validateAttendeeConstraints(attendees: filteredAttendees)
        if case .failure(let error) = attendeeResult {
            validationErrors.append(error.description)
        }

        guard validationErrors.isEmpty else { return }

        // Build notes array
        var notesArray: [String] = []
        if !trimmedNotes.isEmpty {
            notesArray.append(trimmedNotes)
        }

        // Persist: append to existing entry or create new one
        do {
            let today = Date()
            if let existingEntry = persistenceStore.fetchEntry(for: today) {
                try persistenceStore.appendToEntry(
                    date: today,
                    tasks: filteredTasks,
                    attendees: filteredAttendees,
                    notes: notesArray
                )
                // Sync updated entry to spreadsheet
                if let service = spreadsheetService {
                    Task {
                        try? await service.updateEntry(existingEntry)
                    }
                }
            } else {
                let entry = WorkEntry(
                    date: today,
                    tasks: filteredTasks,
                    attendees: filteredAttendees,
                    notes: notesArray
                )
                try persistenceStore.save(entry: entry)
                // Sync new entry to spreadsheet
                if let service = spreadsheetService {
                    Task {
                        try? await service.writeEntry(entry)
                    }
                }
            }
            showConfirmation = true
        } catch {
            errorMessage = "Could not save your entry. Please try again.\n\(error.localizedDescription)"
            showError = true
        }
    }

    private func resetForm() {
        tasks = [""]
        attendees = [""]
        notes = ""
        validationErrors = []
    }

    // MARK: - Helpers

    private var nonEmptyTasks: [String] {
        tasks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var nonEmptyAttendees: [String] {
        attendees.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Preview

#Preview {
    EntryFormView(persistenceStore: PersistenceStore(), spreadsheetService: nil)
}
