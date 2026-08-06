import AppIntents
import Foundation

#if os(macOS)
import AppKit
#endif

/// App Intent that opens the Companion App with the note entry form.
///
/// When triggered from the widget's "Add Note" button, this intent opens
/// the Companion App using its registered URL scheme so the user can
/// quickly add a note for the current day.
struct AddNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Note"
    static var description = IntentDescription("Opens the companion app to add a note.")

    func perform() async throws -> some IntentResult {
        #if os(macOS)
        guard let url = URL(string: "com.retro.dailytracker://note") else {
            return .result()
        }
        NSWorkspace.shared.open(url)
        #endif
        return .result()
    }
}
