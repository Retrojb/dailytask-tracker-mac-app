import Testing
import Foundation

/// Feature: macos-daily-work-widget, Property 5: Spreadsheet row serialization round-trip
///
/// **Validates: Requirements 4.3**
///
/// For any valid WorkEntry, serializing it to the spreadsheet row format (date, tasks, attendees, notes)
/// and then parsing that row back SHALL produce an equivalent WorkEntry with the same date, tasks,
/// attendees, and notes.
@Suite("Spreadsheet Row Serialization Round-Trip")
struct SerializationPropertyTests {

    // MARK: - Random Data Generators

    /// Generates a random date within a reasonable range (2020-2030).
    private func randomDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = Int.random(in: 2020...2030)
        components.month = Int.random(in: 1...12)
        components.day = Int.random(in: 1...28) // Avoid invalid days
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)!
    }

    /// Generates a random string of specified max length using various characters.
    private func randomString(maxLength: Int = 50) -> String {
        let length = Int.random(in: 1...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !@#$%^&*()-_=+[]{}|;:'\",.<>?/~`"
        return String((0..<length).map { _ in characters.randomElement()! })
    }

    /// Generates a random string that may include special characters like newlines, commas, and backslashes.
    private func randomStringWithSpecialChars(maxLength: Int = 50) -> String {
        let length = Int.random(in: 1...maxLength)
        let characters = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n,\\!@#"
        return String((0..<length).map { _ in characters.randomElement()! })
    }

    /// Generates a random array of strings (0 to maxCount items).
    private func randomStringArray(maxCount: Int = 10, stringGenerator: () -> String) -> [String] {
        let count = Int.random(in: 0...maxCount)
        return (0..<count).map { _ in stringGenerator() }
    }

    // MARK: - Property Test

    @Test("Round-trip serialization preserves date, tasks, attendees, and notes across 100 random inputs")
    func serializationRoundTrip() throws {
        for _ in 0..<100 {
            // Generate random valid WorkEntry data
            let date = randomDate()
            let tasks = randomStringArray(maxCount: 10) { randomStringWithSpecialChars(maxLength: 40) }
            let attendees = randomStringArray(maxCount: 10) { randomStringWithSpecialChars(maxLength: 30) }
            let notes = randomStringArray(maxCount: 10) { randomStringWithSpecialChars(maxLength: 40) }

            // Serialize to spreadsheet row
            let row = SpreadsheetRowSerializer.serialize(
                date: date,
                tasks: tasks,
                attendees: attendees,
                notes: notes
            )

            // Parse back from row
            let parsed = try SpreadsheetRowSerializer.parse(row: row)

            // Assert date equivalence (day precision - compare formatted strings)
            let originalDateStr = SpreadsheetRowSerializer.formatDate(date)
            let parsedDateStr = SpreadsheetRowSerializer.formatDate(parsed.date)
            #expect(originalDateStr == parsedDateStr,
                    "Date mismatch: original=\(originalDateStr), parsed=\(parsedDateStr)")

            // Assert tasks equivalence
            #expect(parsed.tasks == tasks,
                    "Tasks mismatch: original=\(tasks), parsed=\(parsed.tasks)")

            // Assert attendees equivalence
            #expect(parsed.attendees == attendees,
                    "Attendees mismatch: original=\(attendees), parsed=\(parsed.attendees)")

            // Assert notes equivalence
            #expect(parsed.notes == notes,
                    "Notes mismatch: original=\(notes), parsed=\(parsed.notes)")
        }
    }

    @Test("Round-trip handles empty arrays correctly")
    func serializationRoundTripEmptyArrays() throws {
        for _ in 0..<100 {
            let date = randomDate()

            // Randomly make some arrays empty
            let tasks: [String] = Bool.random() ? [] : randomStringArray(maxCount: 5) { randomString(maxLength: 20) }
            let attendees: [String] = Bool.random() ? [] : randomStringArray(maxCount: 5) { randomString(maxLength: 20) }
            let notes: [String] = Bool.random() ? [] : randomStringArray(maxCount: 5) { randomString(maxLength: 20) }

            let row = SpreadsheetRowSerializer.serialize(
                date: date,
                tasks: tasks,
                attendees: attendees,
                notes: notes
            )

            let parsed = try SpreadsheetRowSerializer.parse(row: row)

            #expect(parsed.tasks == tasks)
            #expect(parsed.attendees == attendees)
            #expect(parsed.notes == notes)
        }
    }

    @Test("Round-trip handles tasks with embedded newlines")
    func serializationRoundTripNewlinesInTasks() throws {
        for _ in 0..<100 {
            let date = randomDate()
            // Generate tasks that deliberately contain newlines
            let tasks = (0..<Int.random(in: 1...5)).map { _ -> String in
                let parts = (0..<Int.random(in: 2...4)).map { _ in randomString(maxLength: 15) }
                return parts.joined(separator: "\n")
            }
            let attendees = randomStringArray(maxCount: 3) { randomString(maxLength: 20) }
            let notes = (0..<Int.random(in: 1...3)).map { _ -> String in
                let parts = (0..<Int.random(in: 1...3)).map { _ in randomString(maxLength: 10) }
                return parts.joined(separator: "\n")
            }

            let row = SpreadsheetRowSerializer.serialize(
                date: date,
                tasks: tasks,
                attendees: attendees,
                notes: notes
            )

            let parsed = try SpreadsheetRowSerializer.parse(row: row)

            #expect(parsed.tasks == tasks, "Tasks with newlines should round-trip correctly")
            #expect(parsed.attendees == attendees)
            #expect(parsed.notes == notes, "Notes with newlines should round-trip correctly")
        }
    }

    @Test("Round-trip handles attendees with embedded commas")
    func serializationRoundTripCommasInAttendees() throws {
        for _ in 0..<100 {
            let date = randomDate()
            let tasks = randomStringArray(maxCount: 3) { randomString(maxLength: 20) }
            // Generate attendees that deliberately contain commas
            let attendees = (0..<Int.random(in: 1...5)).map { _ -> String in
                let parts = (0..<Int.random(in: 2...3)).map { _ in randomString(maxLength: 10) }
                return parts.joined(separator: ",")
            }
            let notes = randomStringArray(maxCount: 3) { randomString(maxLength: 20) }

            let row = SpreadsheetRowSerializer.serialize(
                date: date,
                tasks: tasks,
                attendees: attendees,
                notes: notes
            )

            let parsed = try SpreadsheetRowSerializer.parse(row: row)

            #expect(parsed.tasks == tasks)
            #expect(parsed.attendees == attendees, "Attendees with commas should round-trip correctly")
            #expect(parsed.notes == notes)
        }
    }

    @Test("Round-trip handles strings with backslashes")
    func serializationRoundTripBackslashes() throws {
        for _ in 0..<100 {
            let date = randomDate()
            // Generate strings with backslashes mixed in
            let tasks = (0..<Int.random(in: 1...5)).map { _ -> String in
                var s = randomString(maxLength: 20)
                // Inject backslashes at random positions
                for _ in 0..<Int.random(in: 1...3) {
                    let pos = s.index(s.startIndex, offsetBy: Int.random(in: 0..<max(1, s.count)))
                    s.insert("\\", at: pos)
                }
                return s
            }
            let attendees = (0..<Int.random(in: 1...3)).map { _ -> String in
                var s = randomString(maxLength: 15)
                s.insert("\\", at: s.startIndex)
                return s
            }
            let notes = randomStringArray(maxCount: 3) { randomString(maxLength: 20) }

            let row = SpreadsheetRowSerializer.serialize(
                date: date,
                tasks: tasks,
                attendees: attendees,
                notes: notes
            )

            let parsed = try SpreadsheetRowSerializer.parse(row: row)

            #expect(parsed.tasks == tasks, "Tasks with backslashes should round-trip correctly")
            #expect(parsed.attendees == attendees, "Attendees with backslashes should round-trip correctly")
            #expect(parsed.notes == notes)
        }
    }
}
