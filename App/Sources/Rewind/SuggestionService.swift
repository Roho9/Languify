import Foundation
import LanguifyKit
import Observation

/// Opt-in proactive vocabulary suggestions.
///
/// When a session ends, and only if the learner enabled suggestions and cloud
/// processing, the final rewind window is transcribed on device and sent once
/// for analysis. Suggestions wait for the learner to accept or dismiss them
/// after the conversation; nothing interrupts it.
///
/// Scope is deliberately limited to the last window: covering the whole
/// conversation would mean keeping a transcript of everything that was said,
/// which conflicts with Languify's data-minimisation rule.
@Observable
final class SuggestionService {
    private(set) var pending: [VocabularyExplanation] = []
    private(set) var isAnalyzing = false

    private let rewind: LiveRewindService
    private let api: LanguifyAPIClient
    private let preferences: PreferencesStore
    private let subscriptions: SubscriptionStore
    private let repository: () -> VocabularyRepository

    init(rewind: LiveRewindService, api: LanguifyAPIClient, preferences: PreferencesStore, subscriptions: SubscriptionStore, repository: @escaping () -> VocabularyRepository) {
        self.rewind = rewind
        self.api = api
        self.preferences = preferences
        self.subscriptions = subscriptions
        self.repository = repository
    }

    var isEnabled: Bool {
        preferences.preferences.proactiveSuggestions
            && preferences.preferences.cloudProcessingConsent
            && subscriptions.resolver.has(.proactiveSuggestions)
    }

    /// Called by the session manager before the buffer is cleared.
    func analyzeEndingSession(_ buffer: RollingAudioBuffer) async {
        guard isEnabled else { return }
        let snapshot = buffer.snapshot(lastSeconds: buffer.capacitySeconds)
        guard snapshot.duration > 5, snapshot.rms >= LiveRewindService.silenceThreshold else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        let language = preferences.language
        do {
            let transcript = try await rewind.transcribe(snapshot, language: language)
            guard !transcript.isEmpty else { return }
            let known = repository().entries(language: language).map(\.transliteration)
            let response = try await api.suggestions(SuggestionsRequest(
                language: language,
                transcript: transcript,
                learner: preferences.learnerSnapshot(recentWords: []),
                knownWords: known
            ))
            let validator = ExplanationValidator(language: language)
            let checked = (try? validator.validate(RewindExplanation(status: .answered, kind: .word, spokenSummary: "-", items: response.items)))?.explanation.items ?? []
            pending = checked
        } catch {
            Log.rewind.notice("Suggestions unavailable")
        }
    }

    func accept(_ item: VocabularyExplanation) {
        repository().save([item], language: preferences.language, heard: nil, fallbackContext: nil, source: .suggestion)
        pending.removeAll { $0 == item }
    }

    func dismiss(_ item: VocabularyExplanation) {
        pending.removeAll { $0 == item }
    }

    func dismissAll() {
        pending.removeAll()
    }
}
