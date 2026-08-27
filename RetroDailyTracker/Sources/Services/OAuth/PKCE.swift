import Foundation
import CryptoKit
import Security

/// Proof Key for Code Exchange (PKCE) support, per RFC 7636.
///
/// PKCE replaces the client secret for public clients such as this app. The app
/// generates a high-entropy random `verifier`, sends only its SHA256 hash
/// (`challenge`) on the authorization request, then presents the original
/// verifier when redeeming the authorization code. An attacker who intercepts
/// the redirect gets a code they cannot exchange, because they never saw the
/// verifier.
///
/// This is why no client secret needs to ship in the app bundle. See
/// https://datatracker.ietf.org/doc/html/rfc7636
struct PKCEChallenge {

    /// Random secret retained in memory for the duration of one authorization flow.
    let verifier: String

    /// BASE64URL(SHA256(ASCII(verifier))), sent as `code_challenge`.
    let challenge: String

    /// The only challenge method this app uses. `plain` is permitted by RFC 7636
    /// but offers no protection against redirect interception.
    static let method = "S256"

    /// Creates a fresh verifier/challenge pair.
    ///
    /// The verifier is 32 random bytes base64url-encoded, yielding 43
    /// characters — the minimum length RFC 7636 §4.1 allows, and entirely within
    /// the permitted unreserved character set.
    init() throws {
        let verifier = try PKCEChallenge.randomURLSafeString(byteCount: 32)

        // Per RFC 7636 §4.2 the hash covers the ASCII *characters* of the
        // verifier, not the random bytes it was derived from.
        let digest = SHA256.hash(data: Data(verifier.utf8))

        self.verifier = verifier
        self.challenge = Data(digest).base64URLEncodedString()
    }

    /// Generates a cryptographically random base64url string, also used for the
    /// OAuth `state` parameter.
    static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)

        guard status == errSecSuccess else {
            throw PKCEError.randomGenerationFailed(status: status)
        }

        return Data(bytes).base64URLEncodedString()
    }
}

/// Failures that can occur while preparing PKCE material.
enum PKCEError: LocalizedError {
    case randomGenerationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed(let status):
            return "Could not generate secure random data for the login request (status \(status))."
        }
    }
}

// MARK: - base64url

extension Data {
    /// Base64url encoding without padding, per RFC 4648 §5.
    ///
    /// Standard base64 uses `+`, `/` and `=`, all of which require escaping in a
    /// URL. OAuth expects the URL-safe alphabet with padding stripped.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
