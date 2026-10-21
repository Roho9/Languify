@preconcurrency import AVFoundation
import Foundation
import LanguifyKit
import Observation

/// Speaks explanations and pronunciations, enforcing the delivery policy:
/// nothing is spoken through the iPhone speaker unless the learner chose
/// Spoken mode, and speech stops immediately if headphones disconnect.
@Observable
@MainActor
final class ResponseDelivery: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession: AudioSessionController
    private let preferences: PreferencesStore
    /// Mutes capture while speaking so the rewind buffer never records Languify itself.
    var setCaptureSuppressed: ((Bool) -> Void)?

    init(audioSession: AudioSessionController, preferences: PreferencesStore) {
        self.audioSession = audioSession
        self.preferences = preferences
        super.init()
        synthesizer.delegate = self
        Task { [weak self] in
            guard let events = self?.audioSession.events() else { return }
            for await event in events where event == .privateOutputLost {
                self?.stop()
            }
        }
    }

    /// Whether an answer would be spoken right now under the current settings.
    var wouldSpeakAnswers: Bool {
        SpeechDeliveryPolicy.shouldSpeak(mode: preferences.preferences.responseMode, headphonesConnected: audioSession.headphonesConnected)
    }

    /// Speaks an English explanation if the policy allows. Returns whether it spoke.
    @discardableResult
    func deliver(summary: String) -> Bool {
        guard wouldSpeakAnswers else { return false }
        speak(summary, languageCode: "en-IN")
        return true
    }

    /// Plays a word or phrase in the heritage language. This is an explicit
    /// tap by the learner, so it plays through the current output.
    func pronounce(_ text: String, language: HeritageLanguage, slow: Bool = false) {
        speak(text, languageCode: language.configuration.synthesisLanguageCode, rate: slow ? 0.32 : 0.45)
    }

    /// True when iOS has a voice for the language. Apple ships a Tamil voice;
    /// a Malayalam voice may be missing, in which case the UI says so.
    func hasVoice(for language: HeritageLanguage) -> Bool {
        AVSpeechSynthesisVoice(language: language.configuration.synthesisLanguageCode) != nil
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func speak(_ text: String, languageCode: String, rate: Float = 0.5) {
        stop()
        if !audioSessionIsActiveForRecording {
            try? audioSession.configureForPlaybackOnly()
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.prefersAssistiveTechnologySettings = true
        setCaptureSuppressed?(true)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private var audioSessionIsActiveForRecording: Bool {
        AVAudioSession.sharedInstance().category == .playAndRecord
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        isSpeaking = false
        // Small tail so room echo of the last word is not captured.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !self.isSpeaking { self.setCaptureSuppressed?(false) }
        }
    }
}

nonisolated extension AudioSessionEvent: Equatable {
    static func == (lhs: AudioSessionEvent, rhs: AudioSessionEvent) -> Bool {
        switch (lhs, rhs) {
        case (.interruptionBegan, .interruptionBegan), (.privateOutputLost, .privateOutputLost),
             (.routeChanged, .routeChanged), (.mediaServicesReset, .mediaServicesReset):
            true
        case (.interruptionEnded(let a), .interruptionEnded(let b)):
            a == b
        default:
            false
        }
    }
}
