# Requirements Document

## Introduction

A macOS widget application that helps users log their daily work activities. The widget sends scheduled reminders on weekdays prompting users to record completed tasks and meetings, supports ad-hoc note entry throughout the day, syncs entries to a Google Sheets or Microsoft Excel spreadsheet, and includes a fun feature to display random animal pictures on demand.

## Glossary

- **Widget**: The macOS WidgetKit-based component displayed in the macOS Notification Center or on the Desktop
- **Companion_App**: The macOS host application that manages scheduling, data persistence, and spreadsheet synchronization
- **Reminder_Service**: The notification scheduling component responsible for delivering daily prompts at the configured time
- **Entry_Form**: The interface presented when a user responds to a reminder or initiates manual entry, containing fields for completed work, meetings, and notes
- **Spreadsheet_Service**: The integration component responsible for writing work log entries to Google Sheets or Microsoft Excel
- **Animal_Picture_Service**: The component that fetches and displays random animal images
- **Work_Entry**: A single daily log record containing date, completed tasks, meeting attendees, and optional notes
- **User**: The person using the widget on their Mac
- **User_Display_Name**: The full name of the macOS logged-in user as reported by the system (NSFullUserName or equivalent)

## Requirements

### Requirement 1: Daily Reminder Notification

**User Story:** As a user, I want to receive a reminder at 3PM EST on weekdays, so that I remember to log my daily work before the end of the business day.

#### Acceptance Criteria

1. WHILE the current day is Monday through Friday, THE Reminder_Service SHALL deliver a local notification at 3:00 PM Eastern Time containing a prompt to log daily work
2. WHILE the current day is Saturday or Sunday, THE Reminder_Service SHALL suppress the daily reminder notification
3. WHEN the user taps the reminder notification, THE Companion_App SHALL present the Entry_Form within 2 seconds
4. IF the Reminder_Service fails to deliver a notification at the scheduled time, THEN THE Companion_App SHALL retry delivery once within 5 minutes of the original schedule
5. IF the retry attempt also fails to deliver the notification, THEN THE Companion_App SHALL log the failure and suppress further delivery attempts until the next scheduled weekday

### Requirement 2: Work Entry Logging

**User Story:** As a user, I want to enter what I completed that day and who I met with, so that I have an accurate daily record of my work activities.

#### Acceptance Criteria

1. WHEN the Entry_Form is presented, THE Entry_Form SHALL display a text field for completed tasks, a text field for meeting attendees, and a text field for additional notes
2. WHEN the user submits the Entry_Form, THE Companion_App SHALL persist the Work_Entry locally with the current date and display a confirmation message indicating the entry was saved
3. THE Entry_Form SHALL allow the user to enter up to 20 completed tasks as a list, each task containing up to 500 characters
4. THE Entry_Form SHALL allow the user to enter up to 30 meeting attendees as a list, each attendee name containing up to 100 characters
5. IF the user submits the Entry_Form with the completed tasks field and the meeting attendees field both empty, THEN THE Companion_App SHALL display a validation message indicating at least one task or one attendee is required and prevent submission
6. IF a Work_Entry already exists for the current date when the user submits the Entry_Form, THEN THE Companion_App SHALL update the existing Work_Entry by appending the new tasks, attendees, and notes to the existing record
7. IF the Companion_App fails to persist the Work_Entry to local storage, THEN THE Companion_App SHALL display an error message indicating the entry could not be saved and retain the entered data in the Entry_Form

### Requirement 3: Ad-Hoc Note Entry

**User Story:** As a user, I want to add notes throughout the day as I remember things, so that I capture work items without waiting for the daily reminder.

#### Acceptance Criteria

1. THE Widget SHALL display a button to initiate ad-hoc note entry at any time
2. WHEN the user taps the add-note button, THE Companion_App SHALL present a note input field pre-associated with the current date, accepting up to 500 characters
3. WHEN the user submits an ad-hoc note, THE Companion_App SHALL append the note to the existing Work_Entry for the current date in chronological order and display a confirmation indicating the note was saved
4. IF no Work_Entry exists for the current date when an ad-hoc note is submitted, THEN THE Companion_App SHALL create a new Work_Entry containing the note
5. IF the user submits an ad-hoc note that is empty or contains only whitespace, THEN THE Companion_App SHALL display a validation message and prevent submission

### Requirement 4: Spreadsheet Synchronization

**User Story:** As a user, I want my daily work entries transcribed to a Google Sheet or Microsoft Excel sheet, so that I have a centralized and shareable record of my work.

#### Acceptance Criteria

1. WHEN a Work_Entry is submitted, THE Spreadsheet_Service SHALL write the entry data to the configured spreadsheet as a new row within 30 seconds
2. WHEN a Work_Entry is updated, THE Spreadsheet_Service SHALL overwrite the corresponding existing row in the configured spreadsheet within 30 seconds
3. WHEN the Spreadsheet_Service writes a Work_Entry, THE Spreadsheet_Service SHALL write a single row containing columns in this order: date (ISO 8601 format), completed tasks, meeting attendees (comma-separated), and notes
4. WHEN the user first configures the application, THE Companion_App SHALL allow the user to select either Google Sheets or Microsoft Excel as the target spreadsheet
5. WHEN the user selects Google Sheets, THE Companion_App SHALL authenticate using OAuth 2.0 and allow the user to specify the target spreadsheet by name or URL
6. WHEN the user selects Microsoft Excel, THE Companion_App SHALL authenticate using Microsoft OAuth and allow the user to specify the target workbook by name or URL
7. IF the Spreadsheet_Service fails to write to the spreadsheet, THEN THE Companion_App SHALL retain the Work_Entry locally and retry synchronization at intervals of 5 minutes
8. IF synchronization fails after 3 retry attempts, THEN THE Companion_App SHALL display a persistent notification to the user indicating which Work_Entry failed to sync
9. IF the spreadsheet authentication token expires during a sync attempt, THEN THE Companion_App SHALL prompt the user to re-authenticate before retrying

### Requirement 5: Random Animal Picture Display

**User Story:** As a user, I want to see a cute random animal picture when I click a button, so that I have a moment of delight during my workday.

#### Acceptance Criteria

1. THE Widget SHALL display a button labeled with an animal icon to fetch a random animal picture
2. WHEN the user taps the animal picture button, THE Animal_Picture_Service SHALL display a loading indicator and fetch a random animal image within 10 seconds
3. THE Animal_Picture_Service SHALL display the fetched image scaled to fit within the widget area while preserving the image aspect ratio
4. IF the Animal_Picture_Service fails to fetch an image within 10 seconds or receives a network error, THEN THE Widget SHALL display a fallback message indicating the image is unavailable and retain the fetch button for retry
5. WHEN the user taps the animal picture button while an image is already displayed, THE Animal_Picture_Service SHALL replace the current image by fetching and displaying a new random animal image

### Requirement 6: Data Persistence

**User Story:** As a user, I want my work entries preserved locally, so that I do not lose data if the spreadsheet service is temporarily unavailable.

#### Acceptance Criteria

1. THE Companion_App SHALL persist all Work_Entry records to local storage immediately upon creation or update
2. WHEN the application is launched, THE Companion_App SHALL load previously saved Work_Entry records and display them in the interface
3. THE Companion_App SHALL retain local Work_Entry records for a minimum of 90 days from their creation date
4. WHEN a Work_Entry record exceeds the 90-day retention period, THE Companion_App SHALL delete it from local storage during the next application launch
5. IF the Companion_App fails to read local storage during launch, THEN THE Companion_App SHALL display an error message and allow the user to create new entries

### Requirement 7: Widget Display

**User Story:** As a user, I want to see a summary of today's entries on my widget, so that I can quickly review what I have logged.

#### Acceptance Criteria

1. THE Widget SHALL display the current date and a summary of today's Work_Entry showing the count of completed tasks, count of meeting attendees, and whether notes exist
2. WHILE no Work_Entry exists for the current date, THE Widget SHALL display a message indicating no entries have been logged today
3. THE Widget SHALL render in both small and medium WidgetKit sizes, where the small size displays the current date and task/meeting counts, and the medium size additionally displays up to 3 completed task descriptions truncated to 40 characters each
4. WHEN a Work_Entry for the current date is created or updated, THE Widget SHALL reflect the updated summary within 15 minutes via WidgetKit timeline reload
5. IF displayed text for a Work_Entry field exceeds the available widget space, THEN THE Widget SHALL truncate the text with a trailing ellipsis

### Requirement 8: Documentation Maintenance

**User Story:** As a developer, I want the README.md to be kept up to date as the project evolves, so that anyone can understand the project structure, setup, and usage at a glance.

#### Acceptance Criteria

1. WHEN a new feature, module, or configuration is added to the project, THE README.md SHALL be updated to reflect the change including relevant sections for Structure, Setup, How to Build, How to Run, and Quirks
2. THE README.md SHALL contain a description of the project, its purpose, and high-level architecture
3. THE README.md SHALL contain instructions for building the project via Xcode and via swift command-line tools
4. THE README.md SHALL contain instructions for running the application after building
5. THE README.md SHALL document any known quirks, limitations, or platform-specific behaviors

### Requirement 9: Build and Execution Tooling

**User Story:** As a developer, I want the project to be buildable and runnable via Xcode and Swift command-line tools, so that I can develop and test using my preferred workflow.

#### Acceptance Criteria

1. THE project SHALL be structured as a valid Xcode project that can be opened and built in Xcode without additional configuration
2. THE project SHALL support building via the `xcodebuild` command-line tool
3. WHERE possible, THE project SHALL support building individual Swift modules using `swift build` via Swift Package Manager
4. THE project SHALL include an Xcode scheme configured for the Companion_App target and the Widget extension target
5. WHEN the project is built via Xcode or command-line tools, THE build output SHALL produce a runnable macOS application bundle
6. THE project SHALL target macOS 14.0 (Sonoma) or later as the minimum deployment target

### Requirement 10: Personalized Notification

**User Story:** As a user, I want the reminder notification to address me by name, so that the experience feels personable and friendly.

#### Acceptance Criteria

1. WHEN the Reminder_Service delivers the daily notification, THE notification body SHALL include the macOS logged-in user's display name (full name) as retrieved from the system
2. THE notification body SHALL use a friendly, personable tone addressing the user by their first name (e.g., "Hey [FirstName], time to log what you accomplished today!")
3. IF the system cannot determine the user's display name, THEN THE notification body SHALL use a generic friendly greeting without a name (e.g., "Hey there, time to log what you accomplished today!")
