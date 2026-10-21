import LanguifyKit
import SwiftUI

/// Full explanation: the sentence, every word with usage notes, replies,
/// alternatives and what the recogniser heard.
struct ExplanationDetailView: View {
    let answer: RewindAnswer
    @Environment(AppServices.self) private var services

    var body: some View {
        let e = answer.explanation
        let language = services.preferences.language
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(answer.query.question).font(.subheadline).foregroundStyle(.secondary)
                Text(e.spokenSummary).font(.title3)

                if let heard = e.heard {
                    Card {
                        SectionHeader(title: "The sentence")
                        PhraseView(nativeScript: heard.nativeScript, transliteration: heard.transliteration, english: heard.englishNatural) {
                            services.delivery.pronounce(heard.nativeScript.isEmpty ? heard.transliteration : heard.nativeScript, language: language)
                        }
                        if let literal = heard.literalGloss, !literal.isEmpty {
                            LabeledContent("Word for word", value: literal).font(.footnote)
                        }
                    }
                }

                ForEach(Array(e.items.enumerated()), id: \.offset) { _, item in
                    WordDetailCard(item: item, language: language)
                }

                if let grammar = e.grammarNote, !grammar.isEmpty {
                    Card {
                        SectionHeader(title: "Grammar")
                        Text(grammar)
                    }
                }

                if !e.suggestedReplies.isEmpty {
                    Card {
                        SectionHeader(title: "Ways to reply")
                        ForEach(e.suggestedReplies, id: \.self) { reply in
                            PhraseView(nativeScript: reply.nativeScript, transliteration: reply.transliteration, english: reply.english) {
                                services.delivery.pronounce(reply.nativeScript.isEmpty ? reply.transliteration : reply.nativeScript, language: language)
                            }
                        }
                    }
                }

                if !e.alternatives.isEmpty || e.uncertaintyNote != nil {
                    Card {
                        SectionHeader(title: "How sure is this?")
                        if let note = e.uncertaintyNote { Text(note) }
                        ForEach(e.alternatives, id: \.transliteration) { alt in
                            LabeledContent(alt.transliteration, value: alt.englishMeaning)
                        }
                    }
                }

                Card {
                    TranscriptPreview(transcript: answer.transcript)
                    Text("Transcribed on your iPhone in \(String(format: "%.1f", Double(answer.latency.transcription.milliseconds) / 1000)) s \u{00B7} explained in \(String(format: "%.1f", Double(answer.latency.explanation.milliseconds) / 1000)) s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(e.items.first?.transliteration ?? "Explanation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WordDetailCard: View {
    let item: VocabularyExplanation
    let language: HeritageLanguage
    @Environment(AppServices.self) private var services

    var body: some View {
        Card {
            PhraseView(nativeScript: item.nativeScript, transliteration: item.transliteration, english: item.englishMeaning, size: .large) {
                services.delivery.pronounce(speakable, language: language)
            }
            HStack {
                Button { services.delivery.pronounce(speakable, language: language, slow: true) } label: {
                    Label("Slowly", systemImage: "tortoise")
                }
                .buttonStyle(.bordered)
                if !services.delivery.hasVoice(for: language) {
                    Text("No \(language.displayName) voice on this iPhone; playback may be approximate.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !item.pronunciationHint.isEmpty {
                LabeledContent("Say it", value: item.pronunciationHint)
            }
            LabeledContent("Here it meant", value: item.contextualMeaning)
            if let pos = item.partOfSpeech { LabeledContent("Part of speech", value: pos) }
            if item.register != .unknown { LabeledContent("Register", value: item.register.rawValue.capitalized) }
            if let note = item.usageNote { NoteRow(symbol: "lightbulb", text: note) }
            if let note = item.culturalNote { NoteRow(symbol: "person.2", text: note) }
            if let note = item.regionalNote { NoteRow(symbol: "map", text: note) }
            if let example = item.example {
                Divider()
                Text("Example").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                PhraseView(nativeScript: example.nativeScript, transliteration: example.transliteration, english: example.english, size: .compact) {
                    services.delivery.pronounce(example.nativeScript.isEmpty ? example.transliteration : example.nativeScript, language: language)
                }
            }
            if !item.related.isEmpty {
                LabeledContent("Related", value: item.related.joined(separator: ", "))
            }
        }
        .font(.subheadline)
    }

    private var speakable: String { item.nativeScript.isEmpty ? item.transliteration : item.nativeScript }
}

struct NoteRow: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
    }
}
