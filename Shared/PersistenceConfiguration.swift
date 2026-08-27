import Foundation
import SwiftData
import os.log

/// Single source of truth for the SwiftData schema and store location.
///
/// # Why this type exists
///
/// Every process that opens the store — the app and the widget extension — must
/// use the **same schema** and the **same file URL**. Violating either rule fails
/// in a confusing way:
///
/// - **Same file, different schemas.** SwiftData migrates the store to whichever
///   model was applied most recently. Opening the store with a schema that omits
///   an entity drops that entity's table, and a later insert through a
///   full-schema context fails with `no such table: Z<ENTITY>`.
///
/// - **Different files.** Each process reads its own store and silently sees no
///   data from the other.
///
/// Both bugs were present before this type was introduced: `PersistenceStore`
/// opened the app's store with a `WorkEntry`-only schema, and the widget pointed
/// at a `default.store` file the app never wrote to.
///
/// # Adding a model
///
/// Add it to ``schema``. That is the only place the model list should appear.
enum PersistenceConfiguration {

    // MARK: - Identifiers

    static let appGroupIdentifier = "group.com.retro.dailytracker"

    /// Store filename. Shared by the app and the widget extension.
    static let storeFileName = "RetroDailyTracker.store"

    /// Named configuration, kept stable so SwiftData resolves the same store.
    static let configurationName = "RetroDailyTracker"

    // MARK: - Schema

    /// Every `@Model` type in the store. Adding a model means adding it here.
    static var schema: Schema {
        Schema([
            WorkEntry.self,
            SpreadsheetConfig.self,
        ])
    }

    // MARK: - Store location

    /// URL of the store inside the App Group container, or `nil` when the
    /// container is unavailable (missing entitlement, or an unsigned build).
    static var storeURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(storeFileName)
    }

    /// Builds the canonical store configuration.
    ///
    /// Falls back to SwiftData's default location when the App Group container is
    /// inaccessible, so the app still runs — though the widget will not see the
    /// data in that case.
    static func makeConfiguration() -> ModelConfiguration {
        if let storeURL {
            return ModelConfiguration(configurationName, schema: schema, url: storeURL)
        }

        Logger(subsystem: "com.retro.dailytracker", category: "Persistence")
            .warning("App Group container unavailable; falling back to the default store location. The widget will not see this data.")

        return ModelConfiguration(configurationName, schema: schema)
    }

    // MARK: - Containers

    /// Creates a container over the canonical schema and store.
    ///
    /// Prefer ``shared`` inside the app. This throwing variant exists for the
    /// widget extension, which degrades to a placeholder rather than crashing.
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [makeConfiguration()])
    }

    /// Process-wide container.
    ///
    /// Two containers over one SQLite file have independent `ModelContext`s and do
    /// not observe each other's writes, so everything within a process shares this
    /// instance. A separate process (the widget) correctly gets its own container;
    /// what matters is that the schema and URL match.
    static let shared: ModelContainer = {
        do {
            return try makeContainer()
        } catch {
            fatalError(
                """
                Failed to create the shared ModelContainer: \(error)

                Store URL: \(storeURL?.path ?? "default location")

                If this followed a schema change during development, the existing \
                store may be incompatible. Deleting the file above will discard \
                local data and let SwiftData recreate it.
                """
            )
        }
    }()
}
