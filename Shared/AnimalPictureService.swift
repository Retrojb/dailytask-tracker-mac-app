import Foundation
import os.log

/// Errors thrown by AnimalPictureService when image fetching fails.
enum AnimalPictureError: Error, LocalizedError {
    case allAPIsFailed(underlyingErrors: [Error])
    case invalidResponse
    case invalidImageURL(String)
    case imageDownloadFailed

    var errorDescription: String? {
        switch self {
        case .allAPIsFailed(let errors):
            let descriptions = errors.map { $0.localizedDescription }.joined(separator: "; ")
            return "All animal picture APIs failed: \(descriptions)"
        case .invalidResponse:
            return "Received an invalid response from the animal picture API"
        case .invalidImageURL(let urlString):
            return "Invalid image URL received: \(urlString)"
        case .imageDownloadFailed:
            return "Failed to download image data from the provided URL"
        }
    }
}

/// A protocol abstracting URLSession for testability.
protocol URLSessionProtocol {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// Fetches random animal images from free public APIs using a fallback chain.
///
/// The service tries APIs in order:
/// 1. randomfox.ca — returns `{ "image": "url", "link": "url" }`
/// 2. random-d.uck.sh — returns `{ "url": "image_url" }`
/// 3. Zoo Animals API — returns animal data with `image_link` field
///
/// Each API is given a 10-second timeout before falling through to the next.
final class AnimalPictureService: AnimalPictureServiceProtocol {

    private let session: URLSessionProtocol
    private let logger = Logger(subsystem: "com.retro.dailytracker", category: "AnimalPictureService")

    /// Timeout in seconds for each individual API request.
    static let perRequestTimeout: TimeInterval = 10

    /// The ordered list of API endpoints to try.
    static let apiEndpoints: [URL] = [
        URL(string: "https://randomfox.ca/floof/")!,
        URL(string: "https://random-d.uck.sh/api/random")!,
        URL(string: "https://zoo-animal-api.herokuapp.com/animals/rand")!
    ]

    init(session: URLSessionProtocol? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.perRequestTimeout
            configuration.timeoutIntervalForResource = Self.perRequestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - AnimalPictureServiceProtocol

    func fetchRandomAnimalImage() async throws -> AnimalImage {
        var errors: [Error] = []

        for (index, endpoint) in Self.apiEndpoints.enumerated() {
            do {
                let image = try await fetchFromAPI(endpoint: endpoint, apiIndex: index)
                logger.info("Successfully fetched animal image from API \(index): \(endpoint.absoluteString)")
                return image
            } catch {
                logger.warning("API \(index) failed (\(endpoint.absoluteString)): \(error.localizedDescription)")
                errors.append(error)
            }
        }

        throw AnimalPictureError.allAPIsFailed(underlyingErrors: errors)
    }

    // MARK: - Private Helpers

    /// Fetches an animal image from a specific API endpoint.
    private func fetchFromAPI(endpoint: URL, apiIndex: Int) async throws -> AnimalImage {
        // Fetch JSON metadata from the API
        let (data, _) = try await session.data(from: endpoint)

        // Parse the image URL from the JSON response
        let imageURLString = try parseImageURL(from: data, apiIndex: apiIndex)

        guard let imageURL = URL(string: imageURLString) else {
            throw AnimalPictureError.invalidImageURL(imageURLString)
        }

        // Download the actual image data
        let (imageData, _) = try await session.data(from: imageURL)

        guard !imageData.isEmpty else {
            throw AnimalPictureError.imageDownloadFailed
        }

        return AnimalImage(url: imageURL, imageData: imageData)
    }

    /// Parses the image URL from the JSON response based on the API format.
    ///
    /// - API 0 (randomfox.ca): `{ "image": "url", "link": "url" }`
    /// - API 1 (random-d.uck.sh): `{ "url": "image_url" }`
    /// - API 2 (Zoo Animals): `{ "image_link": "url", ... }`
    func parseImageURL(from data: Data, apiIndex: Int) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnimalPictureError.invalidResponse
        }

        let imageURL: String?

        switch apiIndex {
        case 0:
            // randomfox.ca: { "image": "url", "link": "url" }
            imageURL = json["image"] as? String
        case 1:
            // random-d.uck.sh: { "url": "image_url" }
            imageURL = json["url"] as? String
        case 2:
            // Zoo Animals API: { "image_link": "url", ... }
            imageURL = json["image_link"] as? String
        default:
            imageURL = nil
        }

        guard let urlString = imageURL, !urlString.isEmpty else {
            throw AnimalPictureError.invalidResponse
        }

        return urlString
    }
}
