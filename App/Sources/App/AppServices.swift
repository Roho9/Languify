import Foundation
import LanguifyKit
import Observation
import SwiftData

/// Composition root. Builds every service once and wires dependencies
/// explicitly; views receive it through the environment and App Intents
/// through `AppDependencyManager`.
@Observable
final class AppServices {
    let preferences: PreferencesStore
    let audioSession: AudioSessionController
    let listening: ListeningSessionManager
    let speechModels: SpeechModelManager
    let delivery: ResponseDelivery
    let api: LanguifyAPIClient
    let tokens: SessionTokenProvider
    let account: AccountService
    let subscriptions: SubscriptionStore
    let rewind: LiveRewindService
    let suggestions: SuggestionService
    let modelContainer: ModelContainer
    let transcriber: SpeechTranscribing

    /// Requested tab, so intents and notifications can navigate.
    var selectedTab: AppTab = .home

    init(inMemoryStore: Bool = false, defaults: UserDefaults = .standard, transcriber: SpeechTranscribing = OnDeviceTranscriber()) {
        let preferences = PreferencesStore(defaults: defaults)
        let audioSession = AudioSessionController()
        let tokens = SessionTokenProvider(baseURL: AppConfiguration.apiBaseURL)
        let api = LanguifyAPIClient(baseURL: AppConfiguration.apiBaseURL, tokens: tokens)
        let container = LanguifySchema.makeContainer(syncWithICloud: defaults.bool(forKey: SyncSettings.key), inMemory: inMemoryStore)
        let listening = ListeningSessionManager(audioSession: audioSession, preferences: preferences)
        let delivery = ResponseDelivery(audioSession: audioSession, preferences: preferences)
        let subscriptions = SubscriptionStore(api: api)
        let context = container.mainContext
        let repository = { VocabularyRepository(context: context) }
        let rewind = LiveRewindService(
            session: listening,
            transcriber: transcriber,
            api: api,
            preferences: preferences,
            delivery: delivery,
            subscriptions: subscriptions,
            repository: repository
        )
        let suggestions = SuggestionService(rewind: rewind, api: api, preferences: preferences, subscriptions: subscriptions, repository: repository)

        self.preferences = preferences
        self.audioSession = audioSession
        self.listening = listening
        self.speechModels = SpeechModelManager()
        self.delivery = delivery
        self.api = api
        self.tokens = tokens
        self.account = AccountService(tokens: tokens, api: api)
        self.subscriptions = subscriptions
        self.rewind = rewind
        self.suggestions = suggestions
        self.modelContainer = container
        self.transcriber = transcriber

        delivery.setCaptureSuppressed = { [weak listening] in listening?.setCaptureSuppressed($0) }
        listening.onSessionWillEnd = { [weak suggestions, weak rewind] buffer in
            await suggestions?.analyzeEndingSession(buffer)
            rewind?.clearSessionHistory()
        }
        ListeningIntentBridge.manager = listening
    }

    var repository: VocabularyRepository { VocabularyRepository(context: modelContainer.mainContext) }

    /// Called once at launch.
    func bootstrap() async {
        guard !AppConfiguration.isRunningTests else { return }
        await speechModels.refresh(for: preferences.language)
        await subscriptions.load()
    }

    /// "Delete all my data": vocabulary, history, preferences, profile,
    /// server-side records and identity. There is never stored audio to delete.
    func deleteEverything() async -> Bool {
        await listening.stop()
        let serverOK = await account.deleteAccount()
        repository.deleteAll()
        preferences.resetAll()
        suggestions.dismissAll()
        rewind.clearSessionHistory()
        return serverOK
    }

    func exportData() throws -> URL {
        let (vocab, reviews) = repository.exportPayload()
        let export = LearningDataExport(exportedAt: Date(), preferences: preferences.preferences, profile: preferences.profile, vocabulary: vocab, reviews: reviews)
        let url = FileManager.default.temporaryDirectory.appending(path: "Languify-Export-\(UsageLedger.dayKey(for: Date())).json")
        try export.encoded().write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

enum SyncSettings {
    static let key = "languify.icloud-sync"
}

enum AppTab: Hashable {
    case home, rewind, vocabulary, learn, profile
}
