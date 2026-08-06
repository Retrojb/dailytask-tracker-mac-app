import Foundation
import AuthenticationServices
import Security
import UserNotifications
import os.log

final class SpreadsheetService: NSObject, SpreadsheetServiceProtocol, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Constants

    private enum OAuthConfig {
        enum Google {
            static let authorizationURL = "https://accounts.google.com/o/oauth2/v2/auth"
            static let tokenURL = "https://oauth2.googleapis.com/token"
            static let scope = "https://www.googleapis.com/auth/spreadsheets"
            // Replace with your registered Google OAuth client ID
            static let clientID = "YOUR_GOOGLE_CLIENT_ID"
            static let clientSecret = "YOUR_GOOGLE_CLIENT_SECRET"
        }

        enum Microsoft {
            static let authorizationURL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
            static let tokenURL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
            static let scope = "Files.ReadWrite"
            // Replace with your registered Microsoft OAuth client ID
            static let clientID = "YOUR_MICROSOFT_CLIENT_ID"
            static let clientSecret = "YOUR_MICROSOFT_CLIENT_SECRET"
        }

        static let callbackURLScheme = "com.retro.dailytracker"
        static let redirectURI = "com.retro.dailytracker://oauth/callback"
    }

    private enum KeychainKeys {
        static let service = "com.retro.dailytracker.oauth"
        static let googleAccessToken = "google_access_token"
        static let googleRefreshToken = "google_refresh_token"
        static let microsoftAccessToken = "microsoft_access_token"
        static let microsoftRefreshToken = "microsoft_refresh_token"
    }

    private enum RetryConfig {
        static let maxRetryAttempts = 3
        static let retryIntervalSeconds: TimeInterval = 300 // 5 minutes
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.retro.dailytracker", category: "SpreadsheetService")
    private let urlSession: URLSession

    private var configuredProvider: SpreadsheetProvider?
    private var configuredSpreadsheetURL: URL?

    /// Tracks retry attempts per WorkEntry id
    private var retryAttempts: [UUID: Int] = [:]

    /// Timer for retry queue processing
    private var retryTimer: Timer?

    // MARK: - Init

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        super.init()
    }

    // MARK: - SpreadsheetServiceProtocol

    func configure(provider: SpreadsheetProvider, spreadsheetURL: URL) async throws {
        configuredProvider = provider
        configuredSpreadsheetURL = spreadsheetURL
        logger.info("Configured spreadsheet service for provider: \(String(describing: provider)), URL: \(spreadsheetURL)")
    }

    func authenticate() async throws {
        guard let provider = configuredProvider else {
            throw SpreadsheetServiceError.notConfigured
        }

        let authorizationCode = try await performOAuthFlow(for: provider)
        try await exchangeAuthorizationCode(authorizationCode, provider: provider)
        logger.info("Authentication successful for \(String(describing: provider))")
    }

    func writeEntry(_ entry: WorkEntry) async throws {
        guard let provider = configuredProvider else {
            throw SpreadsheetServiceError.notConfigured
        }
        guard let spreadsheetURL = configuredSpreadsheetURL else {
            throw SpreadsheetServiceError.notConfigured
        }

        let accessToken = try await getAccessToken()
        let rowValues = SpreadsheetRowSerializer.serialize(entry: entry)

        switch provider {
        case .googleSheets:
            try await writeRowGoogleSheets(
                spreadsheetURL: spreadsheetURL,
                rowValues: rowValues,
                accessToken: accessToken
            )
        case .microsoftExcel:
            try await writeRowMicrosoftExcel(
                spreadsheetURL: spreadsheetURL,
                rowValues: rowValues,
                accessToken: accessToken
            )
        }

        entry.syncStatus = .synced
        logger.info("Successfully wrote entry for date: \(SpreadsheetRowSerializer.formatDate(entry.date))")
    }

    func updateEntry(_ entry: WorkEntry) async throws {
        guard let provider = configuredProvider else {
            throw SpreadsheetServiceError.notConfigured
        }
        guard let spreadsheetURL = configuredSpreadsheetURL else {
            throw SpreadsheetServiceError.notConfigured
        }

        let accessToken = try await getAccessToken()
        let rowValues = SpreadsheetRowSerializer.serialize(entry: entry)
        let dateString = SpreadsheetRowSerializer.formatDate(entry.date)

        switch provider {
        case .googleSheets:
            try await updateRowGoogleSheets(
                spreadsheetURL: spreadsheetURL,
                dateString: dateString,
                rowValues: rowValues,
                accessToken: accessToken
            )
        case .microsoftExcel:
            try await updateRowMicrosoftExcel(
                spreadsheetURL: spreadsheetURL,
                dateString: dateString,
                rowValues: rowValues,
                accessToken: accessToken
            )
        }

        entry.syncStatus = .synced
        logger.info("Successfully updated entry for date: \(dateString)")
    }

    func retryPendingSync() async {
        // This method is called periodically to retry entries with .retrying status.
        // In production, this would query PersistenceStore for entries with .retrying status.
        // The retry logic is integrated into the write/update failure handling.
        logger.info("retryPendingSync invoked — retry queue processing delegated to caller with entry list")
    }

    /// Attempts to sync a single entry, handling retry logic.
    /// Call this for entries with .pending or .retrying status.
    /// Returns true if sync succeeded, false if queued for retry or marked as failed.
    func syncEntryWithRetry(_ entry: WorkEntry, isUpdate: Bool) async -> Bool {
        let entryID = entry.id
        let currentAttempts = retryAttempts[entryID] ?? 0

        if currentAttempts >= RetryConfig.maxRetryAttempts {
            entry.syncStatus = .failed
            retryAttempts.removeValue(forKey: entryID)
            await sendSyncFailureNotification(for: entry)
            logger.error("Entry \(entryID) failed after \(RetryConfig.maxRetryAttempts) attempts")
            return false
        }

        do {
            if isUpdate {
                try await updateEntry(entry)
            } else {
                try await writeEntry(entry)
            }
            retryAttempts.removeValue(forKey: entryID)
            return true
        } catch {
            let newAttempts = currentAttempts + 1
            retryAttempts[entryID] = newAttempts
            logger.warning("Sync attempt \(newAttempts)/\(RetryConfig.maxRetryAttempts) failed for entry \(entryID): \(error.localizedDescription)")

            if newAttempts >= RetryConfig.maxRetryAttempts {
                entry.syncStatus = .failed
                retryAttempts.removeValue(forKey: entryID)
                await sendSyncFailureNotification(for: entry)
                return false
            } else {
                entry.syncStatus = .retrying
                return false
            }
        }
    }

    // MARK: - Google Sheets API

    /// Extracts the spreadsheet ID from a Google Sheets URL.
    /// Expected format: https://docs.google.com/spreadsheets/d/{spreadsheetId}/...
    private func extractGoogleSpreadsheetID(from url: URL) -> String? {
        let components = url.pathComponents
        guard let dIndex = components.firstIndex(of: "d"),
              dIndex + 1 < components.count else {
            return nil
        }
        return components[dIndex + 1]
    }

    /// Appends a new row to a Google Sheets spreadsheet using the values:append endpoint.
    private func writeRowGoogleSheets(spreadsheetURL: URL, rowValues: [String], accessToken: String) async throws {
        guard let spreadsheetID = extractGoogleSpreadsheetID(from: spreadsheetURL) else {
            throw SpreadsheetServiceError.spreadsheetNotFound
        }

        let range = "Sheet1!A:D"
        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        let endpoint = "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange):append"

        guard var urlComponents = URLComponents(string: endpoint) else {
            throw SpreadsheetServiceError.networkError("Invalid endpoint URL")
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "RAW"),
            URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS"),
        ]

        guard let requestURL = urlComponents.url else {
            throw SpreadsheetServiceError.networkError("Failed to construct request URL")
        }

        let body: [String: Any] = [
            "range": range,
            "majorDimension": "ROWS",
            "values": [rowValues],
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await performAuthenticatedRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpreadsheetServiceError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw SpreadsheetServiceError.spreadsheetNotFound
            }
            throw SpreadsheetServiceError.networkError("Google Sheets API returned status \(httpResponse.statusCode)")
        }
    }

    /// Updates an existing row in Google Sheets by finding the row with the matching date
    /// and overwriting it using a PUT to spreadsheets/{id}/values/{range}.
    private func updateRowGoogleSheets(spreadsheetURL: URL, dateString: String, rowValues: [String], accessToken: String) async throws {
        guard let spreadsheetID = extractGoogleSpreadsheetID(from: spreadsheetURL) else {
            throw SpreadsheetServiceError.spreadsheetNotFound
        }

        // First, find the row number for this date by reading column A
        let rowIndex = try await findRowByDate(spreadsheetID: spreadsheetID, dateString: dateString, accessToken: accessToken)

        // PUT to overwrite the specific row
        let range = "Sheet1!A\(rowIndex):D\(rowIndex)"
        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        let endpoint = "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange)"

        guard var urlComponents = URLComponents(string: endpoint) else {
            throw SpreadsheetServiceError.networkError("Invalid endpoint URL")
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "RAW"),
        ]

        guard let requestURL = urlComponents.url else {
            throw SpreadsheetServiceError.networkError("Failed to construct request URL")
        }

        let body: [String: Any] = [
            "range": range,
            "majorDimension": "ROWS",
            "values": [rowValues],
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await performAuthenticatedRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpreadsheetServiceError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SpreadsheetServiceError.networkError("Google Sheets update returned status \(httpResponse.statusCode)")
        }
    }

    /// Searches column A of the spreadsheet for a matching date string, returns the row number.
    private func findRowByDate(spreadsheetID: String, dateString: String, accessToken: String) async throws -> Int {
        let range = "Sheet1!A:A"
        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        let endpoint = "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange)"

        guard let requestURL = URL(string: endpoint) else {
            throw SpreadsheetServiceError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performAuthenticatedRequest(request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SpreadsheetServiceError.networkError("Failed to read spreadsheet column A")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[String]] else {
            // No data found — append as new row instead
            throw SpreadsheetServiceError.networkError("Date \(dateString) not found in spreadsheet")
        }

        // Find the row index (1-based, accounting for the data starting at row 1)
        for (index, row) in values.enumerated() {
            if let cellValue = row.first, cellValue == dateString {
                return index + 1 // Sheets uses 1-based row numbering
            }
        }

        throw SpreadsheetServiceError.networkError("Date \(dateString) not found in spreadsheet")
    }

    // MARK: - Microsoft Graph API

    /// Extracts the workbook item ID or drive path from a Microsoft Excel URL.
    /// Supports OneDrive share URLs and direct Graph API paths.
    private func extractMicrosoftWorkbookPath(from url: URL) -> String? {
        // For simplicity, use the URL's last path component as the item identifier.
        // In production, this would parse various OneDrive URL formats.
        let path = url.path
        guard !path.isEmpty else { return nil }
        return path
    }

    /// Appends a new row to a Microsoft Excel workbook via Graph API.
    private func writeRowMicrosoftExcel(spreadsheetURL: URL, rowValues: [String], accessToken: String) async throws {
        guard let workbookPath = extractMicrosoftWorkbookPath(from: spreadsheetURL) else {
            throw SpreadsheetServiceError.spreadsheetNotFound
        }

        // Microsoft Graph API: POST to add rows to a table or range
        let endpoint = "https://graph.microsoft.com/v1.0/me/drive/root:\(workbookPath):/workbook/worksheets('Sheet1')/range(address='A1:D1')/insert"

        guard let requestURL = URL(string: endpoint) else {
            throw SpreadsheetServiceError.networkError("Invalid Microsoft Graph endpoint URL")
        }

        // Use the table append approach for cleaner row insertion
        let tableEndpoint = "https://graph.microsoft.com/v1.0/me/drive/root:\(workbookPath):/workbook/tables/Table1/rows/add"

        guard let tableRequestURL = URL(string: tableEndpoint) else {
            // Fall back to range-based write
            try await writeRowMicrosoftExcelRange(requestURL: requestURL, rowValues: rowValues, accessToken: accessToken)
            return
        }

        let body: [String: Any] = [
            "values": [rowValues],
        ]

        var request = URLRequest(url: tableRequestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await performAuthenticatedRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpreadsheetServiceError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw SpreadsheetServiceError.spreadsheetNotFound
            }
            throw SpreadsheetServiceError.networkError("Microsoft Graph API returned status \(httpResponse.statusCode)")
        }
    }

    /// Fallback: writes a row using range-based addressing for Microsoft Excel.
    private func writeRowMicrosoftExcelRange(requestURL: URL, rowValues: [String], accessToken: String) async throws {
        let body: [String: Any] = [
            "shift": "Down",
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await performAuthenticatedRequest(request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SpreadsheetServiceError.networkError("Microsoft Graph range insert failed")
        }
    }

    /// Updates an existing row in Microsoft Excel by finding the matching date row.
    private func updateRowMicrosoftExcel(spreadsheetURL: URL, dateString: String, rowValues: [String], accessToken: String) async throws {
        guard let workbookPath = extractMicrosoftWorkbookPath(from: spreadsheetURL) else {
            throw SpreadsheetServiceError.spreadsheetNotFound
        }

        // Read the used range to find the row with the matching date
        let readEndpoint = "https://graph.microsoft.com/v1.0/me/drive/root:\(workbookPath):/workbook/worksheets('Sheet1')/usedRange"

        guard let readURL = URL(string: readEndpoint) else {
            throw SpreadsheetServiceError.networkError("Invalid Microsoft Graph endpoint URL")
        }

        var readRequest = URLRequest(url: readURL)
        readRequest.httpMethod = "GET"
        readRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, readResponse) = try await performAuthenticatedRequest(readRequest)

        guard let httpResponse = readResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SpreadsheetServiceError.networkError("Failed to read Microsoft Excel worksheet")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["values"] as? [[Any]] else {
            throw SpreadsheetServiceError.networkError("Date \(dateString) not found in workbook")
        }

        // Find row index with matching date (0-based)
        var rowIndex: Int?
        for (index, row) in values.enumerated() {
            if let cellValue = row.first as? String, cellValue == dateString {
                rowIndex = index
                break
            }
        }

        guard let foundRow = rowIndex else {
            throw SpreadsheetServiceError.networkError("Date \(dateString) not found in workbook")
        }

        // Update the specific row (1-based in cell address)
        let cellRow = foundRow + 1
        let range = "A\(cellRow):D\(cellRow)"
        let updateEndpoint = "https://graph.microsoft.com/v1.0/me/drive/root:\(workbookPath):/workbook/worksheets('Sheet1')/range(address='\(range)')"

        guard let updateURL = URL(string: updateEndpoint) else {
            throw SpreadsheetServiceError.networkError("Invalid update endpoint URL")
        }

        let updateBody: [String: Any] = [
            "values": [rowValues],
        ]

        var updateRequest = URLRequest(url: updateURL)
        updateRequest.httpMethod = "PATCH"
        updateRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        updateRequest.httpBody = try JSONSerialization.data(withJSONObject: updateBody)

        let (_, updateResponse) = try await performAuthenticatedRequest(updateRequest)

        guard let updateHTTPResponse = updateResponse as? HTTPURLResponse, (200...299).contains(updateHTTPResponse.statusCode) else {
            throw SpreadsheetServiceError.networkError("Microsoft Graph update failed for row \(cellRow)")
        }
    }

    // MARK: - Authenticated Request Helper

    /// Performs an authenticated request, handling 401 responses by refreshing the token and retrying once.
    private func performAuthenticatedRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // Token expired — refresh and retry
            try await handleUnauthorizedResponse()
            let newToken = try await getAccessToken()

            var retryRequest = request
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await urlSession.data(for: retryRequest)
        }

        return (data, response)
    }

    // MARK: - Retry Notification

    /// Sends a persistent notification when sync fails after all retry attempts.
    private func sendSyncFailureNotification(for entry: WorkEntry) async {
        let center = UNUserNotificationCenter.current()
        let dateString = SpreadsheetRowSerializer.formatDate(entry.date)

        let content = UNMutableNotificationContent()
        content.title = "Sync Failed"
        content.body = "Work entry for \(dateString) could not be synced to your spreadsheet after multiple attempts. Please check your connection and try again."
        content.sound = .default
        // Persistent: don't auto-dismiss
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "sync-failure-\(entry.id.uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await center.add(request)
            logger.info("Sent sync failure notification for entry \(dateString)")
        } catch {
            logger.error("Failed to send sync failure notification: \(error.localizedDescription)")
        }
    }

    // MARK: - OAuth Flow

    /// Performs the OAuth authorization flow using ASWebAuthenticationSession.
    private func performOAuthFlow(for provider: SpreadsheetProvider) async throws -> String {
        let authURL = buildAuthorizationURL(for: provider)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: OAuthConfig.callbackURLScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: SpreadsheetServiceError.authenticationFailed(error.localizedDescription))
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: SpreadsheetServiceError.authenticationFailed("No authorization code received"))
                    return
                }

                continuation.resume(returning: code)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                continuation.resume(throwing: SpreadsheetServiceError.authenticationFailed("Failed to start authentication session"))
            }
        }
    }

    /// Builds the OAuth authorization URL for the given provider.
    private func buildAuthorizationURL(for provider: SpreadsheetProvider) -> URL {
        var components: URLComponents

        switch provider {
        case .googleSheets:
            components = URLComponents(string: OAuthConfig.Google.authorizationURL)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: OAuthConfig.Google.clientID),
                URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: OAuthConfig.Google.scope),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]

        case .microsoftExcel:
            components = URLComponents(string: OAuthConfig.Microsoft.authorizationURL)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: OAuthConfig.Microsoft.clientID),
                URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: OAuthConfig.Microsoft.scope),
                URLQueryItem(name: "response_mode", value: "query"),
            ]
        }

        return components.url!
    }

    // MARK: - Token Exchange

    /// Exchanges an authorization code for access and refresh tokens.
    private func exchangeAuthorizationCode(_ code: String, provider: SpreadsheetProvider) async throws {
        let tokenURL: URL
        let body: String

        switch provider {
        case .googleSheets:
            tokenURL = URL(string: OAuthConfig.Google.tokenURL)!
            body = [
                "code=\(code)",
                "client_id=\(OAuthConfig.Google.clientID)",
                "client_secret=\(OAuthConfig.Google.clientSecret)",
                "redirect_uri=\(OAuthConfig.redirectURI)",
                "grant_type=authorization_code",
            ].joined(separator: "&")

        case .microsoftExcel:
            tokenURL = URL(string: OAuthConfig.Microsoft.tokenURL)!
            body = [
                "code=\(code)",
                "client_id=\(OAuthConfig.Microsoft.clientID)",
                "client_secret=\(OAuthConfig.Microsoft.clientSecret)",
                "redirect_uri=\(OAuthConfig.redirectURI)",
                "grant_type=authorization_code",
                "scope=\(OAuthConfig.Microsoft.scope)",
            ].joined(separator: "&")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SpreadsheetServiceError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        try storeTokens(tokenResponse, for: provider)
    }

    // MARK: - Token Refresh

    /// Refreshes the access token using the stored refresh token.
    /// Call this when a 401 response is received.
    func refreshAccessToken(for provider: SpreadsheetProvider) async throws {
        let refreshTokenKey: String
        let tokenURL: URL
        let clientID: String
        let clientSecret: String
        let scope: String?

        switch provider {
        case .googleSheets:
            refreshTokenKey = KeychainKeys.googleRefreshToken
            tokenURL = URL(string: OAuthConfig.Google.tokenURL)!
            clientID = OAuthConfig.Google.clientID
            clientSecret = OAuthConfig.Google.clientSecret
            scope = nil

        case .microsoftExcel:
            refreshTokenKey = KeychainKeys.microsoftRefreshToken
            tokenURL = URL(string: OAuthConfig.Microsoft.tokenURL)!
            clientID = OAuthConfig.Microsoft.clientID
            clientSecret = OAuthConfig.Microsoft.clientSecret
            scope = OAuthConfig.Microsoft.scope
        }

        guard let refreshToken = loadFromKeychain(key: refreshTokenKey) else {
            throw SpreadsheetServiceError.noRefreshToken
        }

        var bodyComponents = [
            "refresh_token=\(refreshToken)",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "grant_type=refresh_token",
        ]

        if let scope = scope {
            bodyComponents.append("scope=\(scope)")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyComponents.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SpreadsheetServiceError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        try storeTokens(tokenResponse, for: provider)
        logger.info("Token refreshed successfully for \(String(describing: provider))")
    }

    /// Returns the current access token for the configured provider, refreshing if needed.
    func getAccessToken() async throws -> String {
        guard let provider = configuredProvider else {
            throw SpreadsheetServiceError.notConfigured
        }

        let accessTokenKey: String
        switch provider {
        case .googleSheets:
            accessTokenKey = KeychainKeys.googleAccessToken
        case .microsoftExcel:
            accessTokenKey = KeychainKeys.microsoftAccessToken
        }

        guard let token = loadFromKeychain(key: accessTokenKey) else {
            throw SpreadsheetServiceError.noAccessToken
        }

        return token
    }

    /// Handles a 401 response by refreshing the token and retrying.
    func handleUnauthorizedResponse() async throws {
        guard let provider = configuredProvider else {
            throw SpreadsheetServiceError.notConfigured
        }

        try await refreshAccessToken(for: provider)
    }

    // MARK: - Keychain Management

    /// Stores access and refresh tokens in the macOS Keychain.
    private func storeTokens(_ tokenResponse: OAuthTokenResponse, for provider: SpreadsheetProvider) throws {
        let accessTokenKey: String
        let refreshTokenKey: String

        switch provider {
        case .googleSheets:
            accessTokenKey = KeychainKeys.googleAccessToken
            refreshTokenKey = KeychainKeys.googleRefreshToken
        case .microsoftExcel:
            accessTokenKey = KeychainKeys.microsoftAccessToken
            refreshTokenKey = KeychainKeys.microsoftRefreshToken
        }

        try saveToKeychain(key: accessTokenKey, value: tokenResponse.accessToken)

        if let refreshToken = tokenResponse.refreshToken {
            try saveToKeychain(key: refreshTokenKey, value: refreshToken)
        }
    }

    /// Saves a value to the macOS Keychain.
    private func saveToKeychain(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SpreadsheetServiceError.keychainError
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: key,
        ]

        // Try to update existing item first
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("Keychain save failed with status: \(addStatus)")
                throw SpreadsheetServiceError.keychainError
            }
        } else if updateStatus != errSecSuccess {
            logger.error("Keychain update failed with status: \(updateStatus)")
            throw SpreadsheetServiceError.keychainError
        }
    }

    /// Loads a value from the macOS Keychain.
    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Deletes a value from the macOS Keychain.
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

// MARK: - Supporting Types

/// OAuth token response structure.
private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

/// Errors specific to the SpreadsheetService.
enum SpreadsheetServiceError: LocalizedError {
    case notConfigured
    case authenticationFailed(String)
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case noAccessToken
    case keychainError
    case networkError(String)
    case spreadsheetNotFound

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Spreadsheet service has not been configured. Call configure() first."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens."
        case .tokenRefreshFailed:
            return "Failed to refresh access token. Please re-authenticate."
        case .noRefreshToken:
            return "No refresh token available. Please re-authenticate."
        case .noAccessToken:
            return "No access token available. Please authenticate."
        case .keychainError:
            return "Failed to access the macOS Keychain."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .spreadsheetNotFound:
            return "The configured spreadsheet could not be found. Please check the URL."
        }
    }
}
