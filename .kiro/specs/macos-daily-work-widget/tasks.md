# Implementation Plan: macOS Daily Work Widget

## Overview

This implementation plan breaks down the macOS Daily Work Widget into incremental coding tasks. The project consists of a Companion App (host application) and a Widget Extension (WidgetKit-based), built with Swift, SwiftUI, and SwiftData targeting macOS 14.0+. Tasks are ordered to build foundational layers first (data models, persistence), then services, then UI, and finally integration/wiring.

## Tasks

- [x] 1. Set up Xcode project structure and shared framework
  - [x] 1.1 Create Xcode project with Companion App and Widget Extension targets
    - Create a new macOS App project named "RetroDailyTracker" with deployment target macOS 14.0
    - Add a WidgetKit Extension target named "DailyTrackerWidget"
    - Configure an App Group (e.g., `group.com.retro.dailytracker`) shared between both targets
    - Add an Xcode scheme that builds both the Companion App and Widget Extension
    - _Requirements: 9.1, 9.4, 9.5, 9.6_

  - [x] 1.2 Define core data models and protocols
    - Create `Models/WorkEntry.swift` with the `@Model` SwiftData class including id, date, tasks, attendees, notes, createdAt, updatedAt, and syncStatus
    - Create `Models/SpreadsheetConfig.swift` with provider, spreadsheetURL, sheetName, lastSyncDate
    - Create `Models/AnimalImageCache.swift` struct with imageData, fetchedAt, sourceURL
    - Define `SyncStatus` enum (pending, synced, failed, retrying)
    - Place shared models in a location accessible by both targets via the App Group
    - _Requirements: 2.3, 2.4, 6.1_

  - [x] 1.3 Define service protocols
    - Create `Protocols/ReminderServiceProtocol.swift` with scheduleWeekdayReminders, cancelAllReminders, handleDeliveryFailure
    - Create `Protocols/PersistenceStoreProtocol.swift` with save, fetchEntry, fetchAllEntries, appendToEntry, purgeExpiredEntries
    - Create `Protocols/SpreadsheetServiceProtocol.swift` with configure, authenticate, writeEntry, updateEntry, retryPendingSync
    - Create `Protocols/AnimalPictureServiceProtocol.swift` with fetchRandomAnimalImage
    - _Requirements: 1.1, 2.2, 3.3, 4.1, 5.2_

- [x] 2. Implement PersistenceStore and data validation
  - [x] 2.1 Implement PersistenceStore with SwiftData
    - Create `Services/PersistenceStore.swift` implementing PersistenceStoreProtocol
    - Configure ModelContainer with App Group container URL for shared access
    - Implement save(entry:) to persist WorkEntry with current timestamp
    - Implement fetchEntry(for:) to query by calendar date (day precision)
    - Implement fetchAllEntries() to return all records sorted by date descending
    - Implement appendToEntry(date:tasks:attendees:notes:) to merge new data into existing entry preserving existing data and chronological order of notes
    - Implement purgeExpiredEntries(retentionDays:) to delete entries older than the retention window
    - _Requirements: 2.2, 2.6, 3.3, 3.4, 6.1, 6.3, 6.4_

  - [x] 2.2 Implement WorkEntry validation logic
    - Create `Validation/WorkEntryValidator.swift` with static validation methods
    - Implement validateSubmission(tasks:attendees:) that rejects if both are empty
    - Implement validateTaskConstraints(tasks:) that enforces max 20 items, each ≤ 500 chars
    - Implement validateAttendeeConstraints(attendees:) that enforces max 30 items, each ≤ 100 chars
    - Implement validateNote(note:) that rejects empty or whitespace-only strings
    - _Requirements: 2.3, 2.4, 2.5, 3.5_

  - [ ] 2.3 Write property tests for WorkEntry validation
    - **Property 1: Work entry validation rejects empty submissions**
    - **Property 9: Task and attendee field length constraints**
    - **Validates: Requirements 2.3, 2.4, 2.5**

  - [x] 2.4 Write property tests for PersistenceStore append and purge
    - **Property 3: Work entry append preserves existing data**
    - **Property 4: Ad-hoc note chronological ordering**
    - **Property 6: Retention policy correctly purges old entries**
    - **Validates: Requirements 2.6, 3.3, 6.3, 6.4**

- [x] 3. Checkpoint - Ensure data layer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement ReminderService
  - [x] 4.1 Implement ReminderService with UNUserNotificationCenter
    - Create `Services/ReminderService.swift` implementing ReminderServiceProtocol
    - Request notification authorization on first use
    - Schedule UNCalendarNotificationTrigger with hour: 15, minute: 0, timeZone: America/New_York for each weekday (Mon-Fri)
    - Implement personalized notification body using NSFullUserName() — split on whitespace, take first component, fall back to "there"
    - Implement retry logic: on delivery failure, schedule a delayed request within 5 minutes
    - Implement handleDeliveryFailure: log failure after retry exhaustion, suppress until next weekday
    - Reschedule notifications on app launch to maintain rolling week coverage
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 10.1, 10.2, 10.3_

  - [x]* 4.2 Write property tests for ReminderService scheduling
    - **Property 7: Notification scheduling targets only weekdays**
    - **Property 10: Personalized notification name extraction**
    - **Validates: Requirements 1.1, 1.2, 10.1, 10.2, 10.3**

  - [x] 4.3 Implement NotificationDelegate for tap handling
    - Create `Delegates/NotificationDelegate.swift` implementing UNUserNotificationCenterDelegate
    - Handle didReceive response to open Entry Form in Companion App
    - Register delegate in App lifecycle (AppDelegate or @main App init)
    - _Requirements: 1.3_

- [x] 5. Implement SpreadsheetService
  - [x] 5.1 Implement OAuth authentication flow
    - Create `Services/SpreadsheetService.swift` implementing SpreadsheetServiceProtocol
    - Implement ASWebAuthenticationSession flow for Google OAuth 2.0
    - Implement ASWebAuthenticationSession flow for Microsoft OAuth
    - Store access/refresh tokens in macOS Keychain using Security framework
    - Handle token refresh on 401 responses
    - _Requirements: 4.4, 4.5, 4.6, 4.9_

  - [x] 5.2 Implement spreadsheet row write and update operations
    - Implement writeEntry(_:) to append a new row via Google Sheets API (POST to spreadsheets/{id}/values:append) or Microsoft Graph API
    - Implement updateEntry(_:) to overwrite existing row for the same date
    - Format row as: date (ISO 8601), tasks (newline-separated), attendees (comma-separated), notes (newline-separated)
    - Implement retry queue: mark failed entries as .retrying, retry every 5 minutes up to 3 attempts
    - After 3 failures, mark as .failed and send persistent notification
    - _Requirements: 4.1, 4.2, 4.3, 4.7, 4.8_

  - [x] 5.3 Write property test for spreadsheet serialization
    - **Property 5: Spreadsheet row serialization round-trip**
    - **Validates: Requirements 4.3**

- [x] 6. Implement AnimalPictureService
  - [x] 6.1 Implement AnimalPictureService with fallback chain
    - Create `Services/AnimalPictureService.swift` implementing AnimalPictureServiceProtocol
    - Implement fetchRandomAnimalImage() with fallback chain: randomfox.ca → random-d.uck.sh → Zoo Animals API
    - Parse JSON responses for each API format
    - Download image data from returned URL
    - Implement 10-second timeout per API before falling through to next
    - Return AnimalImage struct with url and imageData on success
    - On all-fail, throw descriptive error for UI to show fallback message
    - _Requirements: 5.2, 5.3, 5.4_

  - [x] 6.2 Write unit tests for AnimalPictureService
    - Test JSON parsing for each API response format
    - Test fallback chain progression on failure
    - Test timeout behavior
    - _Requirements: 5.2, 5.4_

- [x] 7. Checkpoint - Ensure all service tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Implement Companion App UI
  - [x] 8.1 Implement Entry Form view
    - Create `Views/EntryFormView.swift` using SwiftUI
    - Add text field for completed tasks (list entry with add/remove buttons)
    - Add text field for meeting attendees (list entry with add/remove buttons)
    - Add text field for additional notes
    - Wire validation: show error message if tasks and attendees both empty on submit
    - Wire validation: enforce character and count limits with inline feedback
    - On submit: call PersistenceStore.save or appendToEntry, show confirmation
    - Handle persistence failure: display error, retain form data
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [x] 8.2 Implement Settings view
    - Create `Views/SettingsView.swift` using SwiftUI
    - Add spreadsheet provider picker (Google Sheets / Microsoft Excel)
    - Add spreadsheet URL/name text field
    - Add "Connect" button triggering OAuth flow via SpreadsheetService
    - Display connection status and last sync date
    - _Requirements: 4.4, 4.5, 4.6_

  - [x] 8.3 Implement History view
    - Create `Views/HistoryView.swift` using SwiftUI
    - Display list of past Work_Entry records loaded from PersistenceStore
    - Show date, task count, attendee count, and sync status for each entry
    - Allow tapping an entry to view full details
    - _Requirements: 6.2_

  - [x] 8.4 Implement main App structure and navigation
    - Create or update `RetroDailyTrackerApp.swift` with @main entry point
    - Set up NavigationSplitView or TabView with Entry Form, History, and Settings tabs
    - Initialize ModelContainer with App Group container
    - Register NotificationDelegate on app startup
    - Handle deep link from notification tap to open Entry Form
    - _Requirements: 1.3, 6.2, 6.5, 9.1_

- [ ] 9. Implement Widget Extension
  - [x] 9.1 Implement Widget timeline provider and views
    - Create `Widget/DailyTrackerTimelineProvider.swift` implementing TimelineProvider
    - Generate timeline entries by reading today's WorkEntry from shared SwiftData store
    - Implement `DailyTrackerWidgetView.swift` for both .systemSmall and .systemMedium families
    - Small: display current date, task count, meeting count, add-note button, animal button
    - Medium: additionally display up to 3 task descriptions truncated to 40 chars with ellipsis
    - Display "No entries logged today" when no WorkEntry exists for current date
    - Set timeline reload policy to .after(15 minutes) for near-real-time updates
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x] 9.2 Implement App Intents for widget interactivity
    - Create `Intents/AddNoteIntent.swift` implementing AppIntent
    - AddNoteIntent.perform() opens Companion App with note entry form via URL scheme or NSWorkspace
    - Create `Intents/FetchAnimalIntent.swift` implementing AppIntent
    - FetchAnimalIntent.perform() calls AnimalPictureService, stores result in App Group, reloads widget timeline
    - _Requirements: 3.1, 5.1, 5.5_

  - [ ]* 9.3 Write property test for widget summary counts
    - **Property 8: Widget summary counts match entry data**
    - **Validates: Requirements 7.1**

  - [ ]* 9.4 Write property test for ad-hoc note validation
    - **Property 2: Ad-hoc note validation rejects whitespace-only input**
    - **Validates: Requirements 3.5**

- [x] 10. Checkpoint - Ensure app builds and widget renders
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Integration wiring and final assembly
  - [x] 11.1 Wire SpreadsheetService sync into entry submission flow
    - After PersistenceStore.save in EntryFormView, call SpreadsheetService.writeEntry
    - After appendToEntry, call SpreadsheetService.updateEntry
    - Start background timer for retryPendingSync on app launch
    - Display sync status indicator in History view
    - _Requirements: 4.1, 4.2, 4.7, 4.8_

  - [x] 11.2 Wire ReminderService into app lifecycle
    - Call scheduleWeekdayReminders() on app launch and after notification permission granted
    - Handle permission denied: show in-app banner with link to System Settings
    - _Requirements: 1.1, 1.2_

  - [x] 11.3 Implement data retention purge on app launch
    - Call purgeExpiredEntries(retentionDays: 90) on each app launch
    - Log purge results for debugging
    - _Requirements: 6.3, 6.4_

  - [x] 11.4 Update README.md with project documentation
    - Add project description and purpose
    - Document high-level architecture (Companion App + Widget Extension)
    - Add build instructions for Xcode and xcodebuild CLI
    - Add run instructions
    - Document known quirks and platform requirements (macOS 14.0+, App Group setup)
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 12. Final checkpoint - Ensure all tests pass and app builds cleanly
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation between major phases
- Property tests validate universal correctness properties from the design document
- The project uses Swift, SwiftUI, SwiftData, and WidgetKit — all Apple-native frameworks
- App Group container is critical for sharing data between Companion App and Widget Extension
- OAuth integration (Google/Microsoft) requires registered app credentials configured in the project

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["2.1", "2.2"] },
    { "id": 3, "tasks": ["2.3", "2.4", "4.1"] },
    { "id": 4, "tasks": ["4.2", "4.3", "5.1", "6.1"] },
    { "id": 5, "tasks": ["5.2", "5.3", "6.2"] },
    { "id": 6, "tasks": ["8.1", "8.2", "8.3", "9.1"] },
    { "id": 7, "tasks": ["8.4", "9.2"] },
    { "id": 8, "tasks": ["9.3", "9.4"] },
    { "id": 9, "tasks": ["11.1", "11.2", "11.3", "11.4"] }
  ]
}
```
