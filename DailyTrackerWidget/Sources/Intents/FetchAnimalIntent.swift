import AppIntents
import Foundation
import WidgetKit

/// App Intent that fetches a random animal image and updates the widget.
///
/// When triggered from the widget's "Animal" button, this intent calls
/// AnimalPictureService, stores the resulting image data and metadata in
/// the App Group container, then reloads the widget timeline so the
/// new image is displayed.
struct FetchAnimalIntent: AppIntent {
    static var title: LocalizedStringResource = "Fetch Animal"
    static var description = IntentDescription("Fetches a random animal picture and displays it in the widget.")

    func perform() async throws -> some IntentResult {
        let service = AnimalPictureService()

        do {
            let animalImage = try await service.fetchRandomAnimalImage()
            try storeImageInAppGroup(animalImage)
        } catch {
            // If fetching fails, clear any stale data so the widget shows the fallback
            clearStoredImage()
        }

        // Reload the widget timeline to reflect the new image (or fallback state)
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyTrackerWidget")

        return .result()
    }

    // MARK: - App Group Storage

    /// Stores the animal image data and metadata in the App Group container.
    private func storeImageInAppGroup(_ image: AnimalImage) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.retro.dailytracker"
        ) else {
            return
        }

        // Write image data
        let imageFileURL = containerURL.appendingPathComponent("animal_image.data")
        try image.imageData.write(to: imageFileURL, options: .atomic)

        // Write metadata as JSON
        let metadata: [String: Any] = [
            "sourceURL": image.url.absoluteString,
            "fetchedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        let metadataFileURL = containerURL.appendingPathComponent("animal_image_metadata.json")
        try metadataData.write(to: metadataFileURL, options: .atomic)
    }

    /// Clears any previously stored animal image data.
    private func clearStoredImage() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.retro.dailytracker"
        ) else {
            return
        }

        let imageFileURL = containerURL.appendingPathComponent("animal_image.data")
        let metadataFileURL = containerURL.appendingPathComponent("animal_image_metadata.json")

        try? FileManager.default.removeItem(at: imageFileURL)
        try? FileManager.default.removeItem(at: metadataFileURL)
    }
}
