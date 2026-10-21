import ActivityKit
import AppIntents
import Foundation

/// Live Activity shown while a listening session is active. iOS requires an
/// active Live Activity for audio recording started from an
/// `AudioRecordingIntent`, and it doubles as the always-visible indicator
/// that Languify is listening.
struct ListeningActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: Status
        var rewindSeconds: Int
        var startedAt: Date
        /// Short English gloss of the latest answer, if any. Never transcript text.
        var lastAnswer: String?
    }

    enum Status: String, Codable, Hashable {
        case listening
        case paused
        case interrupted
        case processing

        var label: String {
            switch self {
            case .listening: "Listening"
            case .paused: "Paused"
            case .interrupted: "Mic in use by iOS"
            case .processing: "Thinking"
            }
        }
    }

    var languageName: String
}

/// Ends the listening session. Used by the Live Activity's Stop button and by
/// Siri ("Stop Languify"). As a `LiveActivityIntent` it always runs in the app
/// process, even when triggered from the widget extension.
struct StopListeningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Listening"
    static let description = IntentDescription("Stops Languify's listening session and discards the temporary audio buffer.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "Stopped.")
        #else
        let stopped = await ListeningIntentBridge.stop()
        return .result(dialog: stopped ? "Stopped listening. The temporary audio is gone." : "Languify wasn't listening.")
        #endif
    }
}
