import Foundation
import OSLog

/// Build-time configuration read from Info.plist (populated from xcconfig).
enum AppConfiguration {
    /// Base URL of the Languify backend, or nil when this build has none.
    /// AI features then report "not configured" rather than faking answers.
    static var apiBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "LanguifyAPIBaseURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw), url.scheme != nil
        else { return nil }
        return url
    }

    static let iCloudContainer = "iCloud.app.languify.Languify"

    static let privacyPolicyURL = URL(string: "https://languify.app/privacy")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// True when running under XCTest or UI tests, so services avoid real
    /// network and audio side effects.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }
}

/// Logging that never records conversation content. Only states, durations
/// and error categories are logged.
enum Log {
    static let audio = Logger(subsystem: "app.languify", category: "audio")
    static let speech = Logger(subsystem: "app.languify", category: "speech")
    static let rewind = Logger(subsystem: "app.languify", category: "rewind")
    static let store = Logger(subsystem: "app.languify", category: "store")
    static let account = Logger(subsystem: "app.languify", category: "account")
    static let data = Logger(subsystem: "app.languify", category: "data")
}
