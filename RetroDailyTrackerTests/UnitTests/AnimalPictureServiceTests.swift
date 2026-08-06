import Testing
import Foundation
@testable import RetroDailyTracker

// MARK: - Mock URLSession

/// A mock implementation of URLSessionProtocol that returns predetermined responses
/// or throws predetermined errors based on the requested URL.
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    /// Map of URL to (Data, URLResponse) tuples for successful responses.
    var responses: [URL: (Data, URLResponse)] = [:]

    /// Map of URL to Error for simulated failures.
    var errors: [URL: Error] = [:]

    /// Records which URLs were requested, in order.
    private(set) var requestedURLs: [URL] = []

    func data(from url: URL) async throws -> (Data, URLResponse) {
        requestedURLs.append(url)

        if let error = errors[url] {
            throw error
        }

        guard let response = responses[url] else {
            throw URLError(.badServerResponse)
        }

        return response
    }

    /// Helper to register a successful JSON response for a given URL.
    func setJSONResponse(_ json: [String: Any], for url: URL) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        responses[url] = (data, response)
    }

    /// Helper to register raw data response for a given URL.
    func setDataResponse(_ data: Data, for url: URL) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        responses[url] = (data, response)
    }

    /// Helper to register an error for a given URL.
    func setError(_ error: Error, for url: URL) {
        errors[url] = error
    }
}

// MARK: - JSON Parsing Tests

@Suite("AnimalPictureService - JSON Parsing")
struct AnimalPictureServiceParsingTests {

    @Test("Parses randomfox.ca format correctly (apiIndex 0)")
    func parseRandomFoxFormat() throws {
        let service = AnimalPictureService(session: MockURLSession())
        let json: [String: Any] = ["image": "https://randomfox.ca/images/42.jpg", "link": "https://randomfox.ca/?i=42"]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try service.parseImageURL(from: data, apiIndex: 0)
        #expect(result == "https://randomfox.ca/images/42.jpg")
    }

    @Test("Parses random-d.uck.sh format correctly (apiIndex 1)")
    func parseRandomDuckFormat() throws {
        let service = AnimalPictureService(session: MockURLSession())
        let json: [String: Any] = ["url": "https://random-d.uck.sh/api/randomimg"]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try service.parseImageURL(from: data, apiIndex: 1)
        #expect(result == "https://random-d.uck.sh/api/randomimg")
    }

    @Test("Parses Zoo Animals API format correctly (apiIndex 2)")
    func parseZooAnimalsFormat() throws {
        let service = AnimalPictureService(session: MockURLSession())
        let json: [String: Any] = [
            "name": "Zebra",
            "image_link": "https://zoo-animal-api.herokuapp.com/images/zebra.jpg",
            "latin_name": "Equus quagga"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try service.parseImageURL(from: data, apiIndex: 2)
        #expect(result == "https://zoo-animal-api.herokuapp.com/images/zebra.jpg")
    }

    @Test("Throws error for invalid JSON data")
    func invalidJSONThrowsError() throws {
        let service = AnimalPictureService(session: MockURLSession())
        let invalidData = "not valid json".data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try service.parseImageURL(from: invalidData, apiIndex: 0)
        }
    }

    @Test("Throws invalidResponse for JSON array instead of object")
    func jsonArrayThrowsError() throws {
        let service = AnimalPictureService(session: MockURLSession())
        let arrayData = try JSONSerialization.data(withJSONObject: ["item1", "item2"])

        #expect {
            try service.parseImageURL(from: arrayData, apiIndex: 0)
        } throws: { error in
            guard let pictureError = error as? AnimalPictureError,
                  case .invalidResponse = pictureError else { return false }
            return true
        }
    }

    @Test("Throws invalidResponse when expected URL field is missing")
    func missingURLFieldThrowsError() throws {
        let service = AnimalPictureService(session: MockURLSession())
        // randomfox format expects "image" key, but we provide something else
        let json: [String: Any] = ["link": "https://randomfox.ca/?i=42"]
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect {
            try service.parseImageURL(from: data, apiIndex: 0)
        } throws: { error in
            guard let pictureError = error as? AnimalPictureError,
                  case .invalidResponse = pictureError else { return false }
            return true
        }
    }

    @Test("Throws invalidResponse when URL field is empty string")
    func emptyURLFieldThrowsError() throws {
        let service = AnimalPictureService(session: MockURLSession())
        let json: [String: Any] = ["image": "", "link": "https://randomfox.ca/?i=42"]
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect {
            try service.parseImageURL(from: data, apiIndex: 0)
        } throws: { error in
            guard let pictureError = error as? AnimalPictureError,
                  case .invalidResponse = pictureError else { return false }
            return true
        }
    }

    @Test("Throws invalidResponse for unknown apiIndex")
    func unknownAPIIndexThrowsError() throws {
        let service = AnimalPictureService(session: MockURLSession())
        let json: [String: Any] = ["image": "https://example.com/image.jpg"]
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect {
            try service.parseImageURL(from: data, apiIndex: 99)
        } throws: { error in
            guard let pictureError = error as? AnimalPictureError,
                  case .invalidResponse = pictureError else { return false }
            return true
        }
    }
}

// MARK: - Fallback Chain Tests

@Suite("AnimalPictureService - Fallback Chain")
struct AnimalPictureServiceFallbackTests {

    private let foxURL = AnimalPictureService.apiEndpoints[0]
    private let duckURL = AnimalPictureService.apiEndpoints[1]
    private let zooURL = AnimalPictureService.apiEndpoints[2]

    @Test("Fetches successfully from first API when it succeeds")
    func successFromFirstAPI() async throws {
        let mockSession = MockURLSession()
        let imageURL = URL(string: "https://randomfox.ca/images/1.jpg")!

        // Set up first API metadata response
        mockSession.setJSONResponse(["image": imageURL.absoluteString, "link": "https://randomfox.ca"], for: foxURL)
        // Set up image download response
        mockSession.setDataResponse(Data([0xFF, 0xD8, 0xFF]), for: imageURL)

        let service = AnimalPictureService(session: mockSession)
        let result = try await service.fetchRandomAnimalImage()

        #expect(result.url == imageURL)
        #expect(!result.imageData.isEmpty)
        // Only first API should have been called (plus image download)
        #expect(mockSession.requestedURLs.count == 2)
        #expect(mockSession.requestedURLs[0] == foxURL)
        #expect(mockSession.requestedURLs[1] == imageURL)
    }

    @Test("Falls back to second API when first fails")
    func fallbackToSecondAPI() async throws {
        let mockSession = MockURLSession()
        let imageURL = URL(string: "https://random-d.uck.sh/api/randomimg")!

        // First API fails
        mockSession.setError(URLError(.timedOut), for: foxURL)
        // Second API succeeds
        mockSession.setJSONResponse(["url": imageURL.absoluteString], for: duckURL)
        // Image download succeeds
        mockSession.setDataResponse(Data([0x89, 0x50, 0x4E, 0x47]), for: imageURL)

        let service = AnimalPictureService(session: mockSession)
        let result = try await service.fetchRandomAnimalImage()

        #expect(result.url == imageURL)
        #expect(!result.imageData.isEmpty)
        // First API attempted, then second API, then image download
        #expect(mockSession.requestedURLs[0] == foxURL)
        #expect(mockSession.requestedURLs[1] == duckURL)
    }

    @Test("Falls back to third API when first two fail")
    func fallbackToThirdAPI() async throws {
        let mockSession = MockURLSession()
        let imageURL = URL(string: "https://zoo-animal-api.herokuapp.com/images/lion.jpg")!

        // First two APIs fail
        mockSession.setError(URLError(.timedOut), for: foxURL)
        mockSession.setError(URLError(.cannotConnectToHost), for: duckURL)
        // Third API succeeds
        mockSession.setJSONResponse(["image_link": imageURL.absoluteString, "name": "Lion"], for: zooURL)
        // Image download succeeds
        mockSession.setDataResponse(Data([0x89, 0x50, 0x4E, 0x47]), for: imageURL)

        let service = AnimalPictureService(session: mockSession)
        let result = try await service.fetchRandomAnimalImage()

        #expect(result.url == imageURL)
        #expect(mockSession.requestedURLs[0] == foxURL)
        #expect(mockSession.requestedURLs[1] == duckURL)
        #expect(mockSession.requestedURLs[2] == zooURL)
    }

    @Test("Throws allAPIsFailed when all APIs fail")
    func allAPIsFailThrowsError() async throws {
        let mockSession = MockURLSession()

        // All APIs fail
        mockSession.setError(URLError(.timedOut), for: foxURL)
        mockSession.setError(URLError(.cannotConnectToHost), for: duckURL)
        mockSession.setError(URLError(.badServerResponse), for: zooURL)

        let service = AnimalPictureService(session: mockSession)

        do {
            _ = try await service.fetchRandomAnimalImage()
            Issue.record("Expected allAPIsFailed error to be thrown")
        } catch let error as AnimalPictureError {
            guard case .allAPIsFailed(let underlyingErrors) = error else {
                Issue.record("Expected allAPIsFailed, got: \(error)")
                return
            }
            #expect(underlyingErrors.count == 3)
        }
    }

    @Test("Fetches successfully from fallback API after first returns invalid JSON")
    func fallbackOnInvalidJSON() async throws {
        let mockSession = MockURLSession()
        let imageURL = URL(string: "https://random-d.uck.sh/api/randomimg")!

        // First API returns invalid JSON (missing expected field)
        mockSession.setJSONResponse(["unexpected_field": "value"], for: foxURL)
        // Second API succeeds
        mockSession.setJSONResponse(["url": imageURL.absoluteString], for: duckURL)
        // Image download succeeds
        mockSession.setDataResponse(Data([0x89, 0x50, 0x4E, 0x47]), for: imageURL)

        let service = AnimalPictureService(session: mockSession)
        let result = try await service.fetchRandomAnimalImage()

        #expect(result.url == imageURL)
    }
}

// MARK: - Timeout Configuration Tests

@Suite("AnimalPictureService - Timeout Behavior")
struct AnimalPictureServiceTimeoutTests {

    @Test("Service has 10-second per-request timeout constant")
    func timeoutConstantIsTenSeconds() {
        #expect(AnimalPictureService.perRequestTimeout == 10)
    }

    @Test("Default session is configured with timeout values")
    func defaultSessionUsesTimeout() {
        // When no session is provided, the service creates one with timeout config.
        // We verify this indirectly by checking the static constant is used.
        let service = AnimalPictureService(session: nil)
        // The service initializes successfully — the timeout configuration is applied internally
        // We can only verify the constant value, as the internal session is private.
        #expect(AnimalPictureService.perRequestTimeout == 10)
        _ = service // suppress unused variable warning
    }
}

// MARK: - Error Case Tests

@Suite("AnimalPictureService - Error Cases")
struct AnimalPictureServiceErrorTests {

    private let foxURL = AnimalPictureService.apiEndpoints[0]
    private let duckURL = AnimalPictureService.apiEndpoints[1]
    private let zooURL = AnimalPictureService.apiEndpoints[2]

    @Test("Throws imageDownloadFailed when image data is empty")
    func emptyImageDataThrowsError() async throws {
        let mockSession = MockURLSession()
        let imageURL = URL(string: "https://randomfox.ca/images/1.jpg")!

        // First API returns valid JSON with valid URL
        mockSession.setJSONResponse(["image": imageURL.absoluteString, "link": "https://randomfox.ca"], for: foxURL)
        // Image download returns empty data
        mockSession.setDataResponse(Data(), for: imageURL)
        // Remaining APIs also fail to force the error to propagate
        mockSession.setError(URLError(.timedOut), for: duckURL)
        mockSession.setError(URLError(.timedOut), for: zooURL)

        let service = AnimalPictureService(session: mockSession)

        do {
            _ = try await service.fetchRandomAnimalImage()
            Issue.record("Expected error to be thrown")
        } catch let error as AnimalPictureError {
            guard case .allAPIsFailed(let underlyingErrors) = error else {
                Issue.record("Expected allAPIsFailed wrapping imageDownloadFailed, got: \(error)")
                return
            }
            // The first error in the chain should be imageDownloadFailed
            let firstError = underlyingErrors[0] as? AnimalPictureError
            guard case .imageDownloadFailed = firstError else {
                Issue.record("Expected first underlying error to be imageDownloadFailed, got: \(String(describing: firstError))")
                return
            }
        }
    }

    @Test("Falls through when image download fails with network error")
    func fallsThroughOnImageDownloadNetworkError() async throws {
        let mockSession = MockURLSession()
        let foxURL = AnimalPictureService.apiEndpoints[0]
        let duckURL = AnimalPictureService.apiEndpoints[1]
        let foxImageURL = URL(string: "https://randomfox.ca/images/1.jpg")!
        let duckImageURL = URL(string: "https://random-d.uck.sh/api/randomimg")!

        // First API returns valid JSON but image download fails
        mockSession.setJSONResponse(["image": foxImageURL.absoluteString, "link": "https://randomfox.ca"], for: foxURL)
        mockSession.setError(URLError(.networkConnectionLost), for: foxImageURL)
        // Second API succeeds
        mockSession.setJSONResponse(["url": duckImageURL.absoluteString], for: duckURL)
        mockSession.setDataResponse(Data([0x89, 0x50, 0x4E, 0x47]), for: duckImageURL)

        let service = AnimalPictureService(session: mockSession)
        let result = try await service.fetchRandomAnimalImage()

        #expect(result.url == duckImageURL)
        // Verify the requests: fox API → fox image (failed) → duck API → duck image
        #expect(mockSession.requestedURLs[0] == foxURL)
        #expect(mockSession.requestedURLs[1] == foxImageURL)
        #expect(mockSession.requestedURLs[2] == duckURL)
        #expect(mockSession.requestedURLs[3] == duckImageURL)
    }

    @Test("Throws allAPIsFailed with correct error count")
    func allAPIsFailedContainsAllErrors() async throws {
        let mockSession = MockURLSession()

        mockSession.setError(URLError(.timedOut), for: foxURL)
        mockSession.setError(URLError(.cannotConnectToHost), for: duckURL)
        mockSession.setError(URLError(.notConnectedToInternet), for: zooURL)

        let service = AnimalPictureService(session: mockSession)

        do {
            _ = try await service.fetchRandomAnimalImage()
            Issue.record("Expected allAPIsFailed error")
        } catch let error as AnimalPictureError {
            guard case .allAPIsFailed(let underlyingErrors) = error else {
                Issue.record("Expected allAPIsFailed, got: \(error)")
                return
            }
            #expect(underlyingErrors.count == 3)
            // All three APIs were attempted
            #expect(mockSession.requestedURLs.count == 3)
        }
    }
}

// MARK: - Success Path Tests

@Suite("AnimalPictureService - Success Path")
struct AnimalPictureServiceSuccessTests {

    @Test("Returns valid AnimalImage with URL and data on success")
    func successfulFetchReturnsAnimalImage() async throws {
        let mockSession = MockURLSession()
        let foxURL = AnimalPictureService.apiEndpoints[0]
        let imageURL = URL(string: "https://randomfox.ca/images/99.jpg")!
        let expectedImageData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        mockSession.setJSONResponse(["image": imageURL.absoluteString, "link": "https://randomfox.ca"], for: foxURL)
        mockSession.setDataResponse(expectedImageData, for: imageURL)

        let service = AnimalPictureService(session: mockSession)
        let result = try await service.fetchRandomAnimalImage()

        #expect(result.url == imageURL)
        #expect(result.imageData == expectedImageData)
    }

    @Test("Returns valid AnimalImage from fallback API")
    func successfulFetchFromFallbackReturnsAnimalImage() async throws {
        let mockSession = MockURLSession()
        let foxURL = AnimalPictureService.apiEndpoints[0]
        let duckURL = AnimalPictureService.apiEndpoints[1]
        let imageURL = URL(string: "https://random-d.uck.sh/api/randomimg/duck42.jpg")!
        let expectedImageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

        mockSession.setError(URLError(.networkConnectionLost), for: foxURL)
        mockSession.setJSONResponse(["url": imageURL.absoluteString], for: duckURL)
        mockSession.setDataResponse(expectedImageData, for: imageURL)

        let service = AnimalPictureService(session: mockSession)
        let result = try await service.fetchRandomAnimalImage()

        #expect(result.url == imageURL)
        #expect(result.imageData == expectedImageData)
    }
}
