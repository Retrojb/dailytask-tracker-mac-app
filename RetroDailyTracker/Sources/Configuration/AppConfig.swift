import Foundation

/// Typed access to build-time configuration that arrives via
/// `Config/*.xcconfig` → `Info.plist` → `Bundle.main`.
///
/// Design notes:
///
/// - Values here are **not secrets**. They are readable from the shipped bundle
///   with `plutil -p RetroDailyTracker.app/Contents/Info.plist`. OAuth client IDs
///   are public identifiers; the authorization code exchange is protected by
///   PKCE instead. A client *secret* must never be routed through this type.
///
/// - Missing or unsubstituted values trap immediately with a message naming the
///   key and the fix. A missing Xcode build setting expands to an empty string
///   rather than failing the build, and an xcconfig value containing an
///   unescaped `//` is silently truncated, so both failure modes are caught here
///   at the point of use rather than surfacing later as a confusing
///   `redirect_uri_mismatch` from the provider.
enum AppConfig {

    // MARK: - OAuth

    /// Configuration for a single OAuth provider registration.
    struct OAuthProviderConfig {
        /// Public client identifier issued by the provider.
        let clientID: String
        /// Custom URL scheme that the redirect URI uses.
        let redirectScheme: String
        /// Full redirect URI, which must match the provider registration exactly.
        let redirectURI: String
    }

    static let google = OAuthProviderConfig(
        clientID: requiredValue(for: Key.googleClientID, mustNotContain: "UNSET"),
        redirectScheme: requiredValue(for: Key.googleRedirectScheme, mustNotContain: "UNSET"),
        redirectURI: requiredRedirectURI(
            for: Key.googleRedirectURI,
            expectedScheme: requiredValue(for: Key.googleRedirectScheme, mustNotContain: "UNSET"),
            // Google rejects a custom-scheme redirect that carries an authority
            // component, i.e. `scheme://path` rather than `scheme:/path`.
            requiresEmptyAuthority: true
        )
    )

    static let microsoft = OAuthProviderConfig(
        clientID: requiredValue(for: Key.microsoftClientID, mustNotContain: "UNSET"),
        redirectScheme: requiredValue(for: Key.microsoftRedirectScheme),
        redirectURI: requiredRedirectURI(
            for: Key.microsoftRedirectURI,
            expectedScheme: requiredValue(for: Key.microsoftRedirectScheme)
        )
    )

    // MARK: - Info.plist keys

    private enum Key {
        static let googleClientID = "GoogleOAuthClientID"
        static let googleRedirectScheme = "GoogleOAuthRedirectScheme"
        static let googleRedirectURI = "GoogleOAuthRedirectURI"
        static let microsoftClientID = "MicrosoftOAuthClientID"
        static let microsoftRedirectScheme = "MicrosoftOAuthRedirectScheme"
        static let microsoftRedirectURI = "MicrosoftOAuthRedirectURI"
    }

    // MARK: - Lookup

    /// Reads a non-empty string from the main bundle's Info.plist.
    ///
    /// - Parameter placeholder: when supplied, a value still containing this
    ///   substring is treated as the shipped placeholder from
    ///   `Config/Base.xcconfig` rather than a real registration.
    private static func requiredValue(
        for key: String,
        mustNotContain placeholder: String? = nil
    ) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            fatalError(
                """
                Missing Info.plist key '\(key)'.

                Expected it to be generated from project.yml. If project.yml was \
                edited, regenerate the project with `xcodegen generate`.
                """
            )
        }

        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else {
            fatalError(
                """
                Info.plist key '\(key)' resolved to an empty string.

                This usually means the backing build setting is not defined. \
                Check Config/Base.xcconfig, and note that an undefined Xcode \
                build setting expands to empty rather than failing the build.
                """
            )
        }

        // Catch a `$(FOO)` reference that was never substituted.
        guard !value.contains("$(") else {
            fatalError(
                """
                Info.plist key '\(key)' still contains an unsubstituted build \
                setting reference: '\(value)'.

                The referenced setting is not defined in any xcconfig applied to \
                this target.
                """
            )
        }

        if let placeholder, value.contains(placeholder) {
            fatalError(
                """
                Info.plist key '\(key)' is still the placeholder from \
                Config/Base.xcconfig: '\(value)'.

                Set up your own OAuth client registration:
                  cp Config/Local.xcconfig.example Config/Local.xcconfig
                then fill in the values and rebuild.
                """
            )
        }

        return value
    }

    /// Reads a redirect URI and verifies it is well formed for the provider.
    ///
    /// - Parameter requiresEmptyAuthority: when true, the URI must be of the form
    ///   `scheme:/path` with no authority component. Google's native clients
    ///   reject `scheme://path`, which is easy to introduce by accident because
    ///   it is the conventional shape for every other URL.
    private static func requiredRedirectURI(
        for key: String,
        expectedScheme: String,
        requiresEmptyAuthority: Bool = false
    ) -> String {
        let value = requiredValue(for: key, mustNotContain: "UNSET")

        guard let components = URLComponents(string: value) else {
            fatalError("Info.plist key '\(key)' is not a parseable URI: '\(value)'.")
        }

        guard components.scheme == expectedScheme else {
            fatalError(
                """
                Info.plist key '\(key)' has scheme \
                '\(components.scheme ?? "none")' but '\(expectedScheme)' was \
                expected: '\(value)'.

                A likely cause is writing the URI in an xcconfig as \
                `scheme://path`, where `//` begins a comment and truncates the \
                value to `scheme:`. Write it as `scheme:/$()/path` instead.
                """
            )
        }

        guard !components.path.isEmpty || !(components.host ?? "").isEmpty else {
            fatalError(
                """
                Info.plist key '\(key)' has no path or host component: '\(value)'.

                A redirect URI needs something after the scheme.
                """
            )
        }

        if requiresEmptyAuthority, let host = components.host, !host.isEmpty {
            fatalError(
                """
                Info.plist key '\(key)' must not contain an authority component, \
                but got: '\(value)'.

                This provider requires exactly one slash after the scheme:
                    \(expectedScheme):/\(host)        <- correct
                    \(expectedScheme)://\(host)       <- rejected by the provider

                With two slashes '\(host)' is parsed as the URI authority instead \
                of the path, and the authorization request fails with
                'Error 400: invalid_request'.
                """
            )
        }

        return value
    }
}
