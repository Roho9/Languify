import Foundation
import LanguifyKit
import Observation

/// A question about recent speech.
struct RewindQuery: Equatable {
    var question: String
    var kind: RewindQuestionKind
    var soundsLike: String?
    var userContext: String?
    var detail: DetailLevel = .concise
    var clarification: ClarificationAnswer?
    /// Reuse a transcript from an earlier attempt (clarification follow-ups,
    /// retries) instead of re-reading the buffer, which has moved on.
    var transcript: RewindTranscript?
    /// Uptime when the user asked. Audio after this is excluded.
    var askedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    /// Siri speaks its own dialog, so Languify should not also speak.
    var speakAnswer: Bool = true
}

struct RewindLatency: Equatable {
    var transcription: Duration
    var explanation: Duration
    var total: Duration
}

struct RewindAnswer: Identifiable, Equatable {
    let id = UUID()
    let askedAt: Date
    let query: RewindQuery
    let explanation: RewindExplanation
    let transcript: RewindTranscript
    let savedEntryIDs: [UUID]
    let warnings: [String]
    let latency: RewindLatency
}

enum RewindOutcome: Equatable {
    case answered(RewindAnswer)
    case needsClarification(ClarificationPrompt, RewindQuery)
    /// The window held no recognisable speech. No cloud call was made.
    case noSpeech
    case notListening
    case speechModelMissing
    /// The learner hasn't allowed sending transcripts to the AI service.
    case needsCloudConsent(RewindTranscript)
    case quotaExceeded(resetsAt: Date?)
    case failed(message: String, transcript: RewindTranscript?, retryable: Bool)

    /// One or two sentences suitable for Siri or the Live Activity.
    var spokenText: String {
        switch self {
        case .answered(let a): a.explanation.spokenSummary
        case .needsClarification(let prompt, _): prompt.question
        case .noSpeech: "I didn't catch any speech in the last few seconds."
        case .notListening: "Languify isn't listening right now. Say \u{201C}Start Languify\u{201D} first."
        case .speechModelMissing: "The speech model for this language isn't downloaded yet. Open Languify to finish setup."
        case .needsCloudConsent: "I transcribed it on your phone. Open Languify to allow explanations."
        case .quotaExceeded: "You've used today's free questions. Open Languify for more."
        case .failed(let message, _, _): message
        }
    }
}

/// Runs the Live Rewind pipeline:
/// buffer snapshot -> on-device transcription (heritage language + English, in
/// parallel) -> AI explanation over text only -> validation -> delivery ->
/// vocabulary journal.
///
/// Privacy: audio never leaves the device. Only the transcript of the rewind
/// window is sent, and only with the learner's consent. The audio snapshot is
/// a local copy released when this call returns.
@Observable
final class LiveRewindService {
    private(set) var isWorking = false
    private(set) var stage: String?
    /// Answers from this session, newest first. Memory only; cleared when the session ends.
    private(set) var recentAnswers: [RewindAnswer] = []

    private let session: ListeningSessionManager
    private let transcriber: SpeechTranscribing
    private let api: LanguifyAPIClient
    private let preferences: PreferencesStore
    private let delivery: ResponseDelivery
    private let subscriptions: SubscriptionStore
    private let repository: () -> VocabularyRepository
    private let clock = ContinuousClock()

    /// Speech quieter than this RMS over the whole window is treated as silence.
    static let silenceThreshold: Float = 0.002

    init(
        session: ListeningSessionManager,
        transcriber: SpeechTranscribing,
        api: LanguifyAPIClient,
        preferences: PreferencesStore,
        delivery: ResponseDelivery,
        subscriptions: SubscriptionStore,
        repository: @escaping () -> VocabularyRepository
    ) {
        self.session = session
        self.transcriber = transcriber
        self.api = api
        self.preferences = preferences
        self.delivery = delivery
        self.subscriptions = subscriptions
        self.repository = repository
    }

    func clearSessionHistory() {
        recentAnswers.removeAll()
    }

    func ask(_ query: RewindQuery) async -> RewindOutcome {
        isWorking = true
        session.beginProcessing()
        defer {
            isWorking = false
            stage = nil
        }
        let outcome = await run(query)
        session.endProcessing(answer: outcome.liveActivitySummary)
        if query.speakAnswer, case .answered(let answer) = outcome {
            delivery.deliver(summary: answer.explanation.spokenSummary)
        } else if query.speakAnswer, case .needsClarification(let prompt, _) = outcome {
            delivery.deliver(summary: prompt.question)
        }
        return outcome
    }

    private func run(_ query: RewindQuery) async -> RewindOutcome {
        let started = clock.now
        let language = preferences.language
        let prefs = preferences.preferences

        // 1. Transcript: reuse, or read the buffer.
        var transcript: RewindTranscript
        var transcriptionTime: Duration = .zero
        if let existing = query.transcript {
            transcript = existing
        } else {
            guard session.state.isSessionActive else { return .notListening }
            stage = "Listening back"
            let snapshot = session.buffer.snapshot(lastSeconds: prefs.rewindDuration.seconds, endingAt: query.askedAt)
            guard snapshot.duration >= 0.5, snapshot.rms >= Self.silenceThreshold else { return .noSpeech }

            stage = "Transcribing on device"
            let t0 = clock.now
            do {
                transcript = try await transcribe(snapshot, language: language)
            } catch TranscriptionError.modelNotInstalled {
                return .speechModelMissing
            } catch {
                Log.rewind.error("Transcription failed")
                return .failed(message: (error as? LocalizedError)?.errorDescription ?? "Speech recognition failed.", transcript: nil, retryable: true)
            }
            transcriptionTime = clock.now - t0
            guard !transcript.isEmpty else { return .noSpeech }
        }

        // 2. Consent and quota, checked before any cloud call.
        guard prefs.cloudProcessingConsent else { return .needsCloudConsent(transcript) }
        if case .quotaExhausted = subscriptions.resolver.check(.rewindQuestion, feature: .liveRewind, ledger: preferences.ledger, now: Date()) {
            return .quotaExceeded(resetsAt: nil)
        }

        // 3. Explanation over text.
        stage = "Explaining"
        let repo = repository()
        let detail: DetailLevel = subscriptions.resolver.has(.detailedExplanations) ? query.detail : .concise
        let request = RewindExplainRequest(
            language: language,
            question: query.question,
            kind: query.kind,
            soundsLike: query.soundsLike?.nilIfBlank,
            userContext: query.userContext?.nilIfBlank,
            transcript: transcript,
            learner: preferences.learnerSnapshot(recentWords: repo.recentTransliterations(language: language)),
            clarification: query.clarification,
            detailLevel: detail
        )
        let t1 = clock.now
        let raw: RewindExplanation
        do {
            raw = try await api.explain(request)
        } catch let error as APIError {
            if case .quotaExceeded(_, let resetsAt) = error { return .quotaExceeded(resetsAt: resetsAt) }
            return .failed(message: error.userMessage, transcript: transcript, retryable: error.isRetryable)
        } catch {
            return .failed(message: "Something went wrong getting the explanation.", transcript: transcript, retryable: true)
        }
        let explanationTime = clock.now - t1
        preferences.ledger.record(.rewindQuestion, at: Date())

        // 4. Validate before showing, speaking or saving anything.
        let validated: ExplanationValidator.Result
        do {
            validated = try ExplanationValidator(language: language).validate(raw)
        } catch {
            Log.rewind.error("Explanation failed validation")
            return .failed(message: APIError.invalidResponse.userMessage, transcript: transcript, retryable: true)
        }
        let explanation = validated.explanation

        if explanation.status == .needsClarification, let prompt = explanation.clarification {
            var followUp = query
            followUp.transcript = transcript
            return .needsClarification(prompt, followUp)
        }

        // 5. Learning side effects.
        preferences.profile.record(.askedForMeaning)
        var saved: [UUID] = []
        if prefs.autoSaveVocabulary, explanation.status == .answered || explanation.status == .uncertain, !explanation.items.isEmpty {
            // Uncertain readings are saved only when the learner confirms; see ExplanationCard.
            if explanation.status == .answered {
                saved = repo.save(explanation.items, language: language, heard: explanation.heard, fallbackContext: transcript.lastUtterance, source: .liveRewind).map(\.id)
            }
        }

        let latency = RewindLatency(transcription: transcriptionTime, explanation: explanationTime, total: clock.now - started)
        Log.rewind.info("Rewind answered: transcribe \(latency.transcription.milliseconds, privacy: .public)ms, explain \(latency.explanation.milliseconds, privacy: .public)ms, total \(latency.total.milliseconds, privacy: .public)ms")

        let answer = RewindAnswer(
            askedAt: Date(),
            query: query,
            explanation: explanation,
            transcript: transcript,
            savedEntryIDs: saved,
            warnings: validated.warnings,
            latency: latency
        )
        recentAnswers.insert(answer, at: 0)
        if recentAnswers.count > 20 { recentAnswers.removeLast() }
        return .answered(answer)
    }

    /// Transcribes with the heritage-language model and the English model in
    /// parallel. English failing (e.g. model not yet installed) is tolerated.
    func transcribe(_ snapshot: AudioSnapshot, language: HeritageLanguage) async throws -> RewindTranscript {
        let heritageID = language.configuration.speechLocaleIdentifier
        let englishID = LanguageConfiguration.companionEnglishLocaleIdentifier
        let transcriber = self.transcriber
        async let primary = transcriber.transcribe(snapshot, localeIdentifier: heritageID)
        async let english: [TranscriptSegment]? = try? transcriber.transcribe(snapshot, localeIdentifier: englishID)
        return RewindTranscript(
            languageCode: language.rawValue,
            primary: try await primary,
            english: await english ?? [],
            windowSeconds: snapshot.duration
        )
    }

    /// Saves words from an uncertain answer after the learner confirms them.
    func saveConfirmed(_ answer: RewindAnswer) -> [UUID] {
        repository().save(answer.explanation.items, language: preferences.language, heard: answer.explanation.heard, fallbackContext: answer.transcript.lastUtterance, source: .liveRewind).map(\.id)
    }
}

extension RewindOutcome {
    var liveActivitySummary: String? {
        if case .answered(let a) = self {
            if let item = a.explanation.items.first { return "\(item.transliteration): \(item.englishMeaning)" }
            return a.explanation.heard?.englishNatural
        }
        return nil
    }
}

extension Duration {
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
