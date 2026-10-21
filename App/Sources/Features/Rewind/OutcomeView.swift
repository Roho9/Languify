import LanguifyKit
import SwiftUI

/// Renders the result of a rewind question, including every non-answer case
/// with an honest message and the next useful action.
struct OutcomeView: View {
    let outcome: RewindOutcome
    let onAsk: (RewindQuery) -> Void
    let onUpgrade: () -> Void
    let onRefine: (AskDraft) -> Void
    @Environment(AppServices.self) private var services

    var body: some View {
        switch outcome {
        case .answered(let answer):
            ExplanationCard(answer: answer, onRefine: onRefine, onAsk: onAsk)

        case .needsClarification(let prompt, let query):
            Card {
                Label("Which one did you mean?", systemImage: "questionmark.bubble")
                    .font(.headline)
                Text(prompt.question).font(.body)
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 8) {
                        ForEach(prompt.options, id: \.self) { option in
                            Button {
                                var followUp = query
                                followUp.clarification = ClarificationAnswer(question: prompt.question, chosenOption: option)
                                onAsk(followUp)
                            } label: {
                                Text(option).frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                Button("None of these") {
                    onRefine(AskDraft(question: query.question, reuse: query))
                }
                .buttonStyle(.borderless)
            }

        case .noSpeech:
            MessageCard(symbol: "waveform.slash", title: "Nothing to explain yet", message: "I didn't catch speech in the rewind window. Ask again right after you hear the word.")

        case .notListening:
            MessageCard(symbol: "mic.slash", title: "Not listening", message: "Start a session first. Languify can only explain speech it heard while listening.")

        case .speechModelMissing:
            Card {
                Label("Speech model needed", systemImage: "arrow.down.circle").font(.headline)
                ModelMissingNote()
            }

        case .needsCloudConsent(let transcript):
            Card {
                Label("Transcribed on your iPhone", systemImage: "iphone").font(.headline)
                TranscriptPreview(transcript: transcript)
                Text("To explain it, Languify sends this text (never audio) to its AI service. Languify doesn't store it, and it isn't used to train AI models.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Allow and explain") {
                    services.preferences.preferences.cloudProcessingConsent = true
                    onAsk(RewindQuery(question: RewindQuestionKind.gist.defaultQuestion, kind: .auto, transcript: transcript))
                }
                .primaryAction()
            }

        case .quotaExceeded(let resetsAt):
            Card {
                Label("You've used today's free questions", systemImage: "hourglass").font(.headline)
                Text(resetsAt.map { "More free questions \($0.relativeDescription)." } ?? "Free questions reset tomorrow.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("See Premium", action: onUpgrade).primaryAction()
            }

        case .failed(let message, let transcript, let retryable):
            Card {
                Label("Couldn't explain that", systemImage: "exclamationmark.triangle").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                if let transcript {
                    TranscriptPreview(transcript: transcript)
                }
                if retryable {
                    Button("Try again") {
                        onAsk(RewindQuery(question: RewindQuestionKind.gist.defaultQuestion, kind: .auto, transcript: transcript))
                    }
                    .secondaryAction()
                }
            }
        }
    }
}

struct MessageCard: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        Card {
            Label(title, systemImage: symbol).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the on-device recogniser heard, with low-confidence parts marked.
/// Shown so the learner can judge and correct the input to the explanation.
struct TranscriptPreview: View {
    let transcript: RewindTranscript
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What Languify heard").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(transcript.primary.suffix(4).enumerated()), id: \.offset) { _, segment in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(segment.text).font(.callout)
                    if let c = segment.confidence, c < 0.6 {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Unclear audio")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.tertiary, in: .rect(cornerRadius: 12))
    }
}

struct ExplanationCard: View {
    let answer: RewindAnswer
    let onRefine: (AskDraft) -> Void
    let onAsk: (RewindQuery) -> Void
    @Environment(AppServices.self) private var services
    @State private var savedUncertain = false

    var body: some View {
        let e = answer.explanation
        let language = services.preferences.language
        Card {
            if e.status == .uncertain {
                Label("Best guess. The audio wasn't clear.", systemImage: "questionmark.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(e.spokenSummary).font(.title3)

            if let item = e.items.first {
                Divider()
                PhraseView(nativeScript: item.nativeScript, transliteration: item.transliteration, english: item.englishMeaning, size: .large) {
                    services.delivery.pronounce(item.nativeScript.isEmpty ? item.transliteration : item.nativeScript, language: language)
                }
                if !item.pronunciationHint.isEmpty {
                    Label(item.pronunciationHint, systemImage: "mouth").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let heard = e.heard {
                Divider()
                PhraseView(nativeScript: heard.nativeScript, transliteration: heard.transliteration, english: heard.englishNatural) {
                    services.delivery.pronounce(heard.nativeScript.isEmpty ? heard.transliteration : heard.nativeScript, language: language)
                }
            }

            if !e.suggestedReplies.isEmpty {
                Divider()
                Text("You could say").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(e.suggestedReplies, id: \.self) { reply in
                    PhraseView(nativeScript: reply.nativeScript, transliteration: reply.transliteration, english: reply.english, size: .compact) {
                        services.delivery.pronounce(reply.nativeScript.isEmpty ? reply.transliteration : reply.nativeScript, language: language)
                    }
                }
            }

            if !e.alternatives.isEmpty {
                Text("Could also be: " + e.alternatives.map { "\($0.transliteration) (\($0.englishMeaning))" }.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if !answer.savedEntryIDs.isEmpty || savedUncertain {
                    Label("Saved to journal", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)
                } else if e.status == .uncertain, !e.items.isEmpty {
                    Button("Save anyway") {
                        _ = services.rewind.saveConfirmed(answer)
                        savedUncertain = true
                    }
                    .font(.footnote)
                }
                Spacer()
                Menu {
                    Button("Wrong word? Say what it sounded like", systemImage: "pencil") {
                        var reuse = answer.query
                        reuse.transcript = answer.transcript
                        onRefine(AskDraft(question: "", reuse: reuse))
                    }
                    Button("Explain in more detail", systemImage: "text.magnifyingglass") {
                        var more = answer.query
                        more.transcript = answer.transcript
                        more.detail = .detailed
                        onAsk(more)
                    }
                    .disabled(!services.subscriptions.resolver.has(.detailedExplanations))
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .font(.footnote)
                }
                NavigationLink {
                    ExplanationDetailView(answer: answer)
                } label: {
                    Label("Details", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                }
            }
        }
    }
}

struct AskSheet: View {
    @State var draft: AskDraft
    let onSubmit: (RewindQuery) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Your question") {
                    TextField("e.g. What did she mean by that?", text: $draft.question, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("ask.question")
                }
                Section {
                    TextField("Sounded like\u{2026}", text: $draft.soundsLike)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Roughly how did it sound? (optional)")
                } footer: {
                    Text("Spell it however you like, e.g. \u{201C}madi\u{201D} or \u{201C}vaenum\u{201D}.")
                }
                Section {
                    TextField("e.g. My mom was talking about dinner", text: $draft.context, axis: .vertical)
                } header: {
                    Text("Context (optional)")
                } footer: {
                    Text("Helps with who was speaking or what about. Languify doesn't identify speakers by voice.")
                }
            }
            .navigationTitle("Ask Languify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ask") { onSubmit(makeQuery()) }
                        .disabled(draft.question.nilIfBlank == nil && draft.soundsLike.nilIfBlank == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func makeQuery() -> RewindQuery {
        let question = draft.question.nilIfBlank ?? "What does the word that sounded like \u{201C}\(draft.soundsLike)\u{201D} mean?"
        var query = draft.reuse ?? RewindQuery(question: question, kind: RewindQuestionKind.infer(from: question))
        query.question = question
        query.kind = draft.soundsLike.nilIfBlank != nil ? .word : RewindQuestionKind.infer(from: question)
        query.soundsLike = draft.soundsLike.nilIfBlank
        query.userContext = draft.context.nilIfBlank
        query.clarification = nil
        return query
    }
}

struct SuggestionsCard: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Card {
            SectionHeader(title: "Words from your last conversation", subtitle: "Save the ones you'd like to learn.")
            ForEach(services.suggestions.pending, id: \.transliteration) { item in
                HStack {
                    PhraseView(nativeScript: item.nativeScript, transliteration: item.transliteration, english: item.englishMeaning, size: .compact)
                    Button { services.suggestions.accept(item) } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Save \(item.transliteration)")
                    Button { services.suggestions.dismiss(item) } label: { Image(systemName: "xmark.circle") }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Dismiss \(item.transliteration)")
                }
                .buttonStyle(.borderless)
                .font(.title3)
            }
            Button("Dismiss all") { services.suggestions.dismissAll() }
                .font(.footnote)
        }
    }
}
