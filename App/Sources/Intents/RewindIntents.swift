import AppIntents
import LanguifyKit
import SwiftUI

/// Shared implementation for every "ask Languify" intent.
///
/// These run in Languify's process while a session is active. When Siri is
/// invoked, iOS interrupts Languify's microphone, but the rolling buffer keeps
/// the audio captured before the interruption, which is exactly the speech
/// the learner is asking about.
enum RewindIntentRunner {
    static func run(
        services: AppServices,
        kind: RewindQuestionKind,
        question: String,
        soundsLike: String?,
        askFollowUp: ((String) throws -> Void)? = nil
    ) async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        var query = RewindQuery(question: question, kind: kind, soundsLike: soundsLike, speakAnswer: false)

        // A spoken answer to an earlier clarification question.
        if let pending = PendingClarification.take(), let soundsLike {
            query = pending.query
            query.clarification = ClarificationAnswer(question: pending.prompt.question, chosenOption: soundsLike)
            query.soundsLike = soundsLike
            query.speakAnswer = false
        }

        let outcome = await services.rewind.ask(query)
        let language = services.preferences.language
        switch outcome {
        case .needsClarification(let prompt, let followUp):
            PendingClarification.store(prompt: prompt, query: followUp)
            let options = prompt.options.joined(separator: ", or ")
            // Where the intent has a parameter for it, Siri asks the follow-up
            // in the same exchange and re-runs the intent with the answer.
            try askFollowUp?("\(prompt.question) \(options)?")
            return .result(dialog: IntentDialog(stringLiteral: "\(prompt.question) \(options)?"), view: ClarificationSnippet(prompt: prompt))
        case .answered(let answer):
            return .result(dialog: IntentDialog(stringLiteral: answer.explanation.spokenSummary), view: AnswerSnippet(answer: answer, language: language))
        default:
            return .result(dialog: IntentDialog(stringLiteral: outcome.spokenText), view: MessageSnippet(text: outcome.spokenText))
        }
    }
}

/// Holds a clarification question between two Siri turns for a short time.
enum PendingClarification {
    private static var value: (prompt: ClarificationPrompt, query: RewindQuery, at: Date)?

    static func store(prompt: ClarificationPrompt, query: RewindQuery) {
        value = (prompt, query, Date())
    }

    static func take() -> (prompt: ClarificationPrompt, query: RewindQuery)? {
        defer { value = nil }
        guard let value, Date().timeIntervalSince(value.at) < 120 else { return nil }
        return (value.prompt, value.query)
    }
}

/// "Siri, ask Languify what that word meant."
struct AskWordIntent: AppIntent {
    static let title: LocalizedStringResource = "What Did That Word Mean"
    static let description = IntentDescription("Explains the most recent unfamiliar word Languify heard.")

    @Parameter(title: "Sounds like", description: "Roughly how the word sounded, if you remember.")
    var soundsLike: String?

    @Dependency private var services: AppServices

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let question = soundsLike.map { "What does the word that sounded like \u{201C}\($0)\u{201D} mean?" } ?? RewindQuestionKind.word.defaultQuestion
        return try await RewindIntentRunner.run(services: services, kind: .word, question: question, soundsLike: soundsLike) { followUp in
            throw $soundsLike.needsValueError(IntentDialog(stringLiteral: followUp))
        }
    }
}

/// "Siri, ask Languify what that sentence meant."
struct AskSentenceIntent: AppIntent {
    static let title: LocalizedStringResource = "What Did That Sentence Mean"
    static let description = IntentDescription("Explains the last sentence Languify heard in natural English.")

    @Dependency private var services: AppServices

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try await RewindIntentRunner.run(services: services, kind: .sentence, question: RewindQuestionKind.sentence.defaultQuestion, soundsLike: nil)
    }
}

/// "Siri, ask Languify what was just said."
struct ExplainRecentSpeechIntent: AppIntent {
    static let title: LocalizedStringResource = "Explain What Was Just Said"
    static let description = IntentDescription("Gives the gist of the recent conversation.")

    @Dependency private var services: AppServices

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try await RewindIntentRunner.run(services: services, kind: .gist, question: RewindQuestionKind.gist.defaultQuestion, soundsLike: nil)
    }
}

/// "Siri, ask Languify how to respond."
struct HowToRespondIntent: AppIntent {
    static let title: LocalizedStringResource = "How Do I Respond"
    static let description = IntentDescription("Suggests a natural reply in your heritage language.")

    @Dependency private var services: AppServices

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let language = services.preferences.language.displayName
        return try await RewindIntentRunner.run(services: services, kind: .respond, question: "How would I respond in \(language)?", soundsLike: nil)
    }
}

/// Free-form question, mainly for the Shortcuts app ("Ask Languify" action).
struct AskLanguifyIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Languify"
    static let description = IntentDescription("Ask anything about the last few seconds of conversation.")

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    @Dependency private var services: AppServices

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try await RewindIntentRunner.run(services: services, kind: RewindQuestionKind.infer(from: question), question: question, soundsLike: nil)
    }
}

/// A spoken answer to Languify's clarification question ("the first one", "madi").
struct AnswerClarificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Answer Languify"
    static let description = IntentDescription("Tells Languify which word you meant.")

    @Parameter(title: "Word", requestValueDialog: "Which word did you mean?")
    var choice: String

    @Dependency private var services: AppServices

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        try await RewindIntentRunner.run(services: services, kind: .word, question: "I meant \(choice)", soundsLike: choice)
    }
}

// MARK: - Snippets

private struct AnswerSnippet: View {
    let answer: RewindAnswer
    let language: HeritageLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = answer.explanation.items.first {
                Text(item.transliteration).font(.title2.weight(.semibold))
                if !item.nativeScript.isEmpty { Text(item.nativeScript).font(.title3) }
                Text(item.englishMeaning).foregroundStyle(.secondary)
            } else if let heard = answer.explanation.heard {
                Text(heard.englishNatural).font(.headline)
                Text(heard.transliteration).font(.subheadline).foregroundStyle(.secondary)
            }
            if let reply = answer.explanation.suggestedReplies.first {
                Divider()
                Text(reply.transliteration).font(.headline)
                Text(reply.english).font(.subheadline).foregroundStyle(.secondary)
            }
            if answer.explanation.status == .uncertain {
                Label("Not fully sure about this one", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding()
    }
}

private struct ClarificationSnippet: View {
    let prompt: ClarificationPrompt
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prompt.question).font(.headline)
            ForEach(prompt.options, id: \.self) { Text("\u{2022} \($0)") }
        }
        .padding()
    }
}

private struct MessageSnippet: View {
    let text: String
    var body: some View {
        Text(text).padding()
    }
}
