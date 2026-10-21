import LanguifyKit
import SwiftData
import SwiftUI

/// Spaced-repetition review of saved words, scheduled with FSRS.
struct FlashcardSessionView: View {
    @Environment(AppServices.self) private var services
    @Query private var entries: [VocabularyEntry]
    @State private var queue: [UUID] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var reviewed = 0
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if let entry = current {
                card(entry)
            } else {
                ContentUnavailableView {
                    Label(reviewed > 0 ? "Session complete" : "Nothing to review", systemImage: reviewed > 0 ? "checkmark.seal" : "rectangle.stack")
                } description: {
                    Text(reviewed > 0 ? "You reviewed \(reviewed) word\(reviewed == 1 ? "" : "s"). Languify will bring them back right before you'd forget them." : "New words from Live Rewind appear here. Words you know well are spaced further apart.")
                }
            }
        }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var current: VocabularyEntry? {
        guard index < queue.count else { return nil }
        return entries.first { $0.id == queue[index] }
    }

    private func load() {
        guard !loaded else { return }
        let language = services.preferences.language.rawValue
        let cards = entries.filter { $0.languageCode == language }.map(\.studyCard)
        queue = ReviewQueue.build(from: cards, now: Date()).map(\.id)
        loaded = true
    }

    private func card(_ entry: VocabularyEntry) -> some View {
        let prefs = services.preferences.preferences
        return VStack(spacing: 20) {
            Text("\(index + 1) of \(queue.count)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 16) {
                Text(front(entry, prefs.scriptDisplay))
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                if revealed {
                    Divider()
                    PhraseView(nativeScript: entry.nativeScript, transliteration: entry.transliteration, english: entry.englishMeaning) {
                        services.delivery.pronounce(entry.speakableText, language: entry.language)
                    }
                    if let sentence = entry.contextSentence {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You heard: \(sentence)").font(.subheadline)
                            if let translation = entry.contextTranslation { Text(translation).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NavigationLink {
                        PronunciationPracticeView(target: PracticeTarget(entry: entry))
                    } label: {
                        Label("Say it out loud", systemImage: "mic")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.background.secondary, in: .rect(cornerRadius: 28))
            .onTapGesture { withAnimation(.smooth) { revealed = true } }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(revealed ? "" : "Double tap to reveal")
            Spacer()
            if revealed {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(ReviewGrade.allCases) { grade in
                            Button {
                                record(entry, grade)
                            } label: {
                                Text(grade.label).frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.glass)
                            .tint(tint(grade))
                            .accessibilityIdentifier("grade.\(grade.label)")
                        }
                    }
                }
            } else {
                Button("Show answer") { withAnimation(.smooth) { revealed = true } }
                    .primaryAction()
                    .accessibilityIdentifier("flashcard.reveal")
            }
        }
        .padding()
        .sensoryFeedback(.selection, trigger: index)
    }

    private func front(_ entry: VocabularyEntry, _ display: ScriptDisplay) -> String {
        switch display {
        case .englishFirst: entry.englishMeaning
        case .nativeScriptFirst: entry.nativeScript.isEmpty ? entry.transliteration : entry.nativeScript
        case .transliterationFirst: entry.transliteration
        }
    }

    private func record(_ entry: VocabularyEntry, _ grade: ReviewGrade) {
        services.repository.review(entry, grade: grade)
        services.preferences.profile.record(.flashcardReviewed(grade))
        reviewed += 1
        if grade == .again { queue.append(entry.id) }
        revealed = false
        index += 1
    }

    private func tint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .accentColor
        case .easy: .green
        }
    }
}
