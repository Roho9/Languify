import LanguifyKit
import SwiftUI

struct VocabularyDetailView: View {
    @Bindable var entry: VocabularyEntry
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        let language = entry.language
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    PhraseView(nativeScript: entry.nativeScript, transliteration: entry.transliteration, english: entry.englishMeaning, size: .large) {
                        services.delivery.pronounce(entry.speakableText, language: language)
                    }
                    HStack {
                        Button { services.delivery.pronounce(entry.speakableText, language: language, slow: true) } label: {
                            Label("Slowly", systemImage: "tortoise")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        StatusBadge(status: entry.status)
                    }
                    if !entry.pronunciationHint.isEmpty {
                        LabeledContent("Say it", value: entry.pronunciationHint)
                    }
                    if !entry.contextualMeaning.isEmpty {
                        LabeledContent("In context", value: entry.contextualMeaning)
                    }
                    if let original = entry.originalEnglishMeaning {
                        Text("You corrected this from \u{201C}\(original)\u{201D}.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)

                if let sentence = entry.contextSentence {
                    Card {
                        SectionHeader(title: "Where you heard it", subtitle: entry.encounteredAt.formatted(date: .abbreviated, time: .shortened))
                        PhraseView(nativeScript: entry.contextSentenceNative ?? "", transliteration: sentence, english: entry.contextTranslation ?? "", size: .compact) {
                            services.delivery.pronounce(entry.contextSentenceNative ?? sentence, language: language)
                        }
                        if entry.encounterCount > 1 {
                            Text("Heard \(entry.encounterCount) times").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let example = entry.exampleTransliteration {
                    Card {
                        SectionHeader(title: "Example")
                        PhraseView(nativeScript: entry.exampleNative ?? "", transliteration: example, english: entry.exampleEnglish ?? "", size: .compact) {
                            services.delivery.pronounce(entry.exampleNative ?? example, language: language)
                        }
                    }
                }

                let notes = [entry.usageNote, entry.culturalNote, entry.regionalNote].compactMap { $0 }
                if !notes.isEmpty || entry.partOfSpeech != nil || !entry.relatedWords.isEmpty {
                    Card {
                        SectionHeader(title: "Usage")
                        if let pos = entry.partOfSpeech { LabeledContent("Part of speech", value: pos) }
                        if entry.register != .unknown { LabeledContent("Register", value: entry.register.rawValue.capitalized) }
                        ForEach(notes, id: \.self) { NoteRow(symbol: "lightbulb", text: $0) }
                        if !entry.relatedWords.isEmpty { LabeledContent("Related", value: entry.relatedWords.joined(separator: ", ")) }
                    }
                    .font(.subheadline)
                }

                Card {
                    SectionHeader(title: "Practice")
                    LabeledContent("Reviews", value: "\(entry.reviewCount)")
                    if let due = entry.dueAt { LabeledContent("Next review", value: due.relativeDescription) }
                    LabeledContent("Source", value: entry.source.label)
                    Toggle("Mark as mastered", isOn: Binding(get: { entry.manuallyMastered }, set: { services.repository.setMastered(entry, $0) }))
                    NavigationLink {
                        PronunciationPracticeView(target: PracticeTarget(entry: entry))
                    } label: {
                        Label("Practise saying it", systemImage: "mic")
                    }
                }
                .font(.subheadline)
            }
            .padding()
        }
        .navigationTitle(entry.transliteration)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { services.repository.toggleFavorite(entry) } label: {
                    Label("Favorite", systemImage: entry.isFavorite ? "star.fill" : "star")
                }
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing) { EditVocabularyView(entry: entry) }
        .confirmationDialog("Delete \(entry.transliteration)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                services.repository.delete(entry)
                dismiss()
            }
        } message: {
            Text("Its review history is deleted too.")
        }
    }
}

struct EditVocabularyView: View {
    let entry: VocabularyEntry?
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var nativeScript = ""
    @State private var transliteration = ""
    @State private var meaning = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Transliteration (e.g. madi)", text: $transliteration)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(services.preferences.language.configuration.scriptName + " (optional)", text: $nativeScript)
                    TextField("English meaning", text: $meaning)
                } footer: {
                    if entry != nil {
                        Text("Your corrections are kept even if Languify explains this word again.")
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add Word" : "Edit Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(transliteration.nilIfBlank == nil || meaning.nilIfBlank == nil)
                }
            }
            .onAppear {
                if let entry {
                    nativeScript = entry.nativeScript
                    transliteration = entry.transliteration
                    meaning = entry.englishMeaning
                }
            }
        }
    }

    private func save() {
        let repo = services.repository
        if let entry {
            repo.correct(entry, nativeScript: nativeScript.trimmingCharacters(in: .whitespaces), transliteration: transliteration.trimmingCharacters(in: .whitespaces), englishMeaning: meaning.trimmingCharacters(in: .whitespaces))
        } else {
            let new = VocabularyEntry(language: services.preferences.language, nativeScript: nativeScript.trimmingCharacters(in: .whitespaces), transliteration: transliteration.trimmingCharacters(in: .whitespaces), englishMeaning: meaning.trimmingCharacters(in: .whitespaces))
            repo.context.insert(new)
            try? repo.context.save()
        }
        dismiss()
    }
}
