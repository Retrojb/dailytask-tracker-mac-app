import Foundation

/// A spreadsheet row representation for a WorkEntry.
/// Columns: date (ISO 8601), tasks (newline-separated), attendees (comma-separated), notes (newline-separated).
struct SpreadsheetRow: Equatable {
    let date: String
    let tasks: String
    let attendees: String
    let notes: String
}

/// Errors that can occur during spreadsheet row parsing.
enum SpreadsheetRowParseError: Error, Equatable {
    case invalidColumnCount(Int)
    case invalidDateFormat(String)
}

/// Provides serialization and deserialization between WorkEntry data and spreadsheet row format.
///
/// Spreadsheet row format (per design doc):
/// | Column | Content                | Format                          |
/// |--------|------------------------|---------------------------------|
/// | A      | Date                   | ISO 8601 (YYYY-MM-DD)           |
/// | B      | Completed Tasks        | Newline-separated list          |
/// | C      | Meeting Attendees      | Comma-separated                 |
/// | D      | Notes                  | Newline-separated, chronological|
///
/// Edge case handling:
/// - Tasks/notes containing literal newlines are escaped as "\\n" before joining
/// - Attendees containing commas are escaped as "\\," before joining
/// - Empty arrays serialize to empty strings
enum SpreadsheetRowSerializer {

    // MARK: - Escape Characters

    /// Sentinel used to escape literal newlines within individual items.
    private static let newlineEscape = "\\n"
    /// Sentinel used to escape literal commas within attendee names.
    private static let commaEscape = "\\,"
    /// Sentinel used to escape literal backslashes (must be processed first on escape, last on unescape).
    private static let backslashEscape = "\\\\"

    // MARK: - Serialization

    /// Serializes a WorkEntry into an array of column strings for the spreadsheet API.
    /// Returns: [date, tasks, attendees, notes] as an array of strings.
    static func serialize(entry: WorkEntry) -> [String] {
        let row = serialize(date: entry.date, tasks: entry.tasks, attendees: entry.attendees, notes: entry.notes)
        return [row.date, row.tasks, row.attendees, row.notes]
    }

    /// Serializes WorkEntry data into spreadsheet row columns.
    /// - Parameters:
    ///   - date: The entry date.
    ///   - tasks: Array of completed task descriptions.
    ///   - attendees: Array of meeting attendee names.
    ///   - notes: Array of notes in chronological order.
    /// - Returns: A `SpreadsheetRow` with properly formatted column values.
    static func serialize(date: Date, tasks: [String], attendees: [String], notes: [String]) -> SpreadsheetRow {
        let dateString = formatDate(date)
        let tasksString = serializeNewlineSeparated(tasks)
        let attendeesString = serializeCommaSeparated(attendees)
        let notesString = serializeNewlineSeparated(notes)

        return SpreadsheetRow(
            date: dateString,
            tasks: tasksString,
            attendees: attendeesString,
            notes: notesString
        )
    }

    /// Parses a spreadsheet row back into WorkEntry components.
    /// - Parameter row: The spreadsheet row to parse.
    /// - Returns: A tuple of (date, tasks, attendees, notes).
    /// - Throws: `SpreadsheetRowParseError` if the row cannot be parsed.
    static func parse(row: SpreadsheetRow) throws -> (date: Date, tasks: [String], attendees: [String], notes: [String]) {
        guard let date = parseDate(row.date) else {
            throw SpreadsheetRowParseError.invalidDateFormat(row.date)
        }

        let tasks = deserializeNewlineSeparated(row.tasks)
        let attendees = deserializeCommaSeparated(row.attendees)
        let notes = deserializeNewlineSeparated(row.notes)

        return (date: date, tasks: tasks, attendees: attendees, notes: notes)
    }

    // MARK: - Date Formatting

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter
    }()

    /// Formats a Date to ISO 8601 date-only string (YYYY-MM-DD).
    static func formatDate(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    /// Parses an ISO 8601 date-only string back to a Date.
    static func parseDate(_ string: String) -> Date? {
        return dateFormatter.date(from: string)
    }

    // MARK: - Newline-Separated Serialization (Tasks, Notes)

    /// Serializes an array of strings as a newline-separated string.
    /// Escapes backslashes first, then literal newlines within individual items.
    private static func serializeNewlineSeparated(_ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        let escaped = items.map { item in
            item
                .replacingOccurrences(of: "\\", with: backslashEscape)
                .replacingOccurrences(of: "\n", with: newlineEscape)
        }
        return escaped.joined(separator: "\n")
    }

    /// Deserializes a newline-separated string back into an array of strings.
    /// Splits on unescaped newlines and unescapes sequences character-by-character.
    private static func deserializeNewlineSeparated(_ string: String) -> [String] {
        guard !string.isEmpty else { return [] }

        // Split on actual newlines (the delimiter), then unescape each part
        let parts = string.components(separatedBy: "\n")
        return parts.map { part in
            unescapeNewlineSeparatedPart(part)
        }
    }

    /// Unescapes a single part from a newline-separated field.
    /// Handles `\\` → `\` and `\n` → newline, processing character by character
    /// to avoid ambiguity between escaped backslash followed by 'n' vs escaped newline.
    private static func unescapeNewlineSeparatedPart(_ string: String) -> String {
        var result = ""
        var i = string.startIndex

        while i < string.endIndex {
            let char = string[i]
            if char == "\\" {
                let next = string.index(after: i)
                if next < string.endIndex {
                    let nextChar = string[next]
                    if nextChar == "\\" {
                        // Escaped backslash
                        result.append("\\")
                        i = string.index(after: next)
                        continue
                    } else if nextChar == "n" {
                        // Escaped newline
                        result.append("\n")
                        i = string.index(after: next)
                        continue
                    }
                }
                // Lone backslash (shouldn't happen with proper escaping, but handle gracefully)
                result.append(char)
                i = string.index(after: i)
            } else {
                result.append(char)
                i = string.index(after: i)
            }
        }

        return result
    }

    // MARK: - Comma-Separated Serialization (Attendees)

    /// Serializes an array of strings as a comma-separated string.
    /// Escapes backslashes first, then literal commas within individual items.
    private static func serializeCommaSeparated(_ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        let escaped = items.map { item in
            item
                .replacingOccurrences(of: "\\", with: backslashEscape)
                .replacingOccurrences(of: ",", with: commaEscape)
        }
        return escaped.joined(separator: ",")
    }

    /// Deserializes a comma-separated string back into an array of strings.
    /// Handles escaped commas properly by splitting only on unescaped commas.
    private static func deserializeCommaSeparated(_ string: String) -> [String] {
        guard !string.isEmpty else { return [] }

        // Split on commas that are NOT preceded by a backslash
        var parts: [String] = []
        var current = ""
        var i = string.startIndex

        while i < string.endIndex {
            let char = string[i]
            if char == "\\" {
                // Check what follows the backslash
                let next = string.index(after: i)
                if next < string.endIndex {
                    let nextChar = string[next]
                    if nextChar == "," {
                        // Escaped comma - add literal comma
                        current.append(",")
                        i = string.index(after: next)
                        continue
                    } else if nextChar == "\\" {
                        // Escaped backslash - add literal backslash
                        current.append("\\")
                        i = string.index(after: next)
                        continue
                    }
                }
                // Lone backslash (shouldn't happen with proper escaping, but handle gracefully)
                current.append(char)
                i = string.index(after: i)
            } else if char == "," {
                // Unescaped comma - delimiter
                parts.append(current)
                current = ""
                i = string.index(after: i)
            } else {
                current.append(char)
                i = string.index(after: i)
            }
        }
        parts.append(current)

        return parts
    }
}
