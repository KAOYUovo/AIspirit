import Foundation

public struct PrivacyBlocklist: Codable, Equatable, Sendable {
    public var appNamePatterns: [String]
    public var bundleIdentifierPatterns: [String]
    public var windowTitlePatterns: [String]

    public init(
        appNamePatterns: [String] = Self.defaultAppNamePatterns,
        bundleIdentifierPatterns: [String] = Self.defaultBundleIdentifierPatterns,
        windowTitlePatterns: [String] = Self.defaultWindowTitlePatterns
    ) {
        self.appNamePatterns = appNamePatterns
        self.bundleIdentifierPatterns = bundleIdentifierPatterns
        self.windowTitlePatterns = windowTitlePatterns
    }

    public static let defaults = PrivacyBlocklist()

    public func match(_ snapshot: FrontAppSnapshot) -> PrivacyBlockMatch? {
        if let pattern = firstMatch(value: snapshot.appName, patterns: appNamePatterns) {
            return PrivacyBlockMatch(field: .appName, pattern: pattern, value: snapshot.appName)
        }

        if let bundleIdentifier = snapshot.bundleIdentifier,
           let pattern = firstMatch(value: bundleIdentifier, patterns: bundleIdentifierPatterns) {
            return PrivacyBlockMatch(field: .bundleIdentifier, pattern: pattern, value: bundleIdentifier)
        }

        for title in snapshot.windowTitles {
            if let pattern = firstMatch(value: title, patterns: windowTitlePatterns) {
                return PrivacyBlockMatch(field: .windowTitle, pattern: pattern, value: title)
            }
        }

        return nil
    }

    private func firstMatch(value: String, patterns: [String]) -> String? {
        let normalizedValue = value.lowercased()
        return patterns.first { pattern in
            normalizedValue.contains(pattern.lowercased())
        }
    }

    public static let defaultAppNamePatterns = [
        "1password",
        "keychain access",
        "password",
        "authenticator"
    ]

    public static let defaultBundleIdentifierPatterns = [
        "com.1password",
        "com.apple.keychainaccess"
    ]

    public static let defaultWindowTitlePatterns = [
        "password",
        "passcode",
        "verification code",
        "two-factor",
        "2fa",
        "one-time code",
        "secret",
        "private key",
        "recovery key",
        "wallet"
    ]
}

public struct PrivacyBlockMatch: Codable, Equatable, Sendable {
    public var field: PrivacyBlockField
    public var pattern: String
    public var value: String

    public init(field: PrivacyBlockField, pattern: String, value: String) {
        self.field = field
        self.pattern = pattern
        self.value = value
    }
}

public enum PrivacyBlockField: String, Codable, Sendable {
    case appName
    case bundleIdentifier
    case windowTitle
}
