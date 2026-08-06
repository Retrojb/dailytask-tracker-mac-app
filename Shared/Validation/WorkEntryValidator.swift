import Foundation

/// Errors that can occur when validating work entry data.
enum WorkEntryValidationError: Error, Equatable, CustomStringConvertible {
    case emptySubmission
    case tooManyTasks(count: Int)
    case taskTooLong(index: Int, length: Int)
    case tooManyAttendees(count: Int)
    case attendeeNameTooLong(index: Int, length: Int)
    case noteIsEmpty

    var description: String {
        switch self {
        case .emptySubmission:
            return "At least one task or one attendee is required."
        case .tooManyTasks(let count):
            return "Too many tasks: \(count) provided, maximum is 20."
        case .taskTooLong(let index, let length):
            return "Task at index \(index) is too long: \(length) characters, maximum is 500."
        case .tooManyAttendees(let count):
            return "Too many attendees: \(count) provided, maximum is 30."
        case .attendeeNameTooLong(let index, let length):
            return "Attendee name at index \(index) is too long: \(length) characters, maximum is 100."
        case .noteIsEmpty:
            return "Note must not be empty or contain only whitespace."
        }
    }
}

/// Provides static validation methods for work entry fields.
enum WorkEntryValidator {

    // MARK: - Constants

    static let maxTasks = 20
    static let maxTaskLength = 500
    static let maxAttendees = 30
    static let maxAttendeeNameLength = 100

    // MARK: - Submission Validation

    /// Validates that a submission has at least one task or one attendee.
    /// - Parameters:
    ///   - tasks: The list of completed tasks.
    ///   - attendees: The list of meeting attendees.
    /// - Returns: A `Result` indicating success or a validation error.
    static func validateSubmission(tasks: [String], attendees: [String]) -> Result<Void, WorkEntryValidationError> {
        if tasks.isEmpty && attendees.isEmpty {
            return .failure(.emptySubmission)
        }
        return .success(())
    }

    // MARK: - Task Constraints

    /// Validates task list constraints: max 20 items, each up to 500 characters.
    /// - Parameter tasks: The list of completed tasks.
    /// - Returns: A `Result` indicating success or the first constraint violation found.
    static func validateTaskConstraints(tasks: [String]) -> Result<Void, WorkEntryValidationError> {
        if tasks.count > maxTasks {
            return .failure(.tooManyTasks(count: tasks.count))
        }
        for (index, task) in tasks.enumerated() {
            if task.count > maxTaskLength {
                return .failure(.taskTooLong(index: index, length: task.count))
            }
        }
        return .success(())
    }

    // MARK: - Attendee Constraints

    /// Validates attendee list constraints: max 30 items, each up to 100 characters.
    /// - Parameter attendees: The list of meeting attendees.
    /// - Returns: A `Result` indicating success or the first constraint violation found.
    static func validateAttendeeConstraints(attendees: [String]) -> Result<Void, WorkEntryValidationError> {
        if attendees.count > maxAttendees {
            return .failure(.tooManyAttendees(count: attendees.count))
        }
        for (index, attendee) in attendees.enumerated() {
            if attendee.count > maxAttendeeNameLength {
                return .failure(.attendeeNameTooLong(index: index, length: attendee.count))
            }
        }
        return .success(())
    }

    // MARK: - Note Validation

    /// Validates that a note is not empty or whitespace-only.
    /// - Parameter note: The note string to validate.
    /// - Returns: A `Result` indicating success or a validation error.
    static func validateNote(note: String) -> Result<Void, WorkEntryValidationError> {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.noteIsEmpty)
        }
        return .success(())
    }
}
