import AppIntents
import LanguifyKit
import UIKit

/// "Siri, start Languify."
///
/// Adopts `AudioRecordingIntent`, which lets iOS start microphone capture from
/// Siri even when Languify is not in the foreground, on the condition that a
/// Live Activity is shown for the whole recording (the session manager starts
/// one). Microphone permission must already have been granted in the app:
/// iOS cannot show a permission prompt from Siri.
struct StartListeningIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Listening"
    static let description = IntentDescription("Starts a Languify listening session that keeps only the last few seconds of audio on your iPhone.")

    @Dependency private var services: AppServices

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let listening = services.listening
        if listening.state.isCapturing {
            return .result(dialog: "Languify is already listening.")
        }
        let fromBackground = UIApplication.shared.applicationState != .active
        // Siri holds the microphone while it is speaking, so the first attempt
        // can fail with an interruption. Retry briefly before giving up.
        for attempt in 0..<3 {
            await listening.start(fromBackground: fromBackground)
            if listening.state.isCapturing { break }
            if case .failed(.microphonePermissionDenied) = listening.state { break }
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(1_200)) }
        }

        switch listening.state {
        case .listening, .processing:
            let seconds = Int(listening.rewindSeconds)
            return .result(dialog: "Listening. I'll keep the last \(seconds) seconds.")
        case .failed(.microphonePermissionDenied):
            return .result(dialog: "Open Languify once to allow microphone access, then try again.")
        default:
            return .result(dialog: IntentDialog(stringLiteral: listening.lastError ?? "I couldn't start listening. Open Languify and tap Start Listening."))
        }
    }
}
