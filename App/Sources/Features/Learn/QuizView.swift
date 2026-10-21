import LanguifyKit
import SwiftData
import SwiftUI

/// Multiple-choice quiz generated on device from the learner's own words.
struct QuizView: View {
    @Environment(AppServices.self) private var services
    @Query private var entries: [VocabularyEntry]
    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var picked: Int?
    @State private var correct = 0
    @State private var built = false

    var body: some View {
        Group {
            if !built {
                ProgressView()
            } else if questions.isEmpty {
                ContentUnavailableView("Not enough words yet", systemImage: "checklist", description: Text("Save at least four words with different meanings to build a quiz."))
            } else if index >= questions.count {
                ContentUnavailableView {
                    Label("\(correct) of \(questions.count) correct", systemImage: "checkmark.seal")
                } description: {
                    Text("Missed words will come up sooner in your flashcards.")
                } actions: {
                    Button("Another quiz") { build(force: true) }.buttonStyle(.borderedProminent)
                }
            } else {
                question(questions[index])
            }
        }
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { build(force: false) }
    }

    private func build(force: Bool) {
        guard force || !built else { return }
        let language = services.preferences.language
        let cards = entries.filter { $0.languageCode == language.rawValue }.map(\.studyCard)
        var rng = SystemRandomNumberGenerator()
        questions = QuizGenerator().makeQuiz(from: cards, count: 8, includeListening: services.delivery.hasVoice(for: language), using: &rng)
        index = 0
        correct = 0
        picked = nil
        built = true
    }

    private func question(_ q: QuizQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProgressView(value: Double(index), total: Double(questions.count))
                Text(q.prompt).font(.title2.weight(.semibold))
                if let audio = q.audioText {
                    Button {
                        services.delivery.pronounce(audio, language: services.preferences.language)
                    } label: {
                        Label("Play", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .onAppear { services.delivery.pronounce(audio, language: services.preferences.language) }
                }
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                    Button {
                        guard picked == nil else { return }
                        picked = i
                        let isRight = i == q.correctIndex
                        if isRight { correct += 1 }
                        services.preferences.profile.record(.quizAnswered(dimension: q.type == .listening ? .listening : .vocabulary, correct: isRight))
                        if !isRight, let entry = entries.first(where: { $0.id == q.cardID }) {
                            services.repository.review(entry, grade: .again)
                        }
                    } label: {
                        HStack {
                            Text(option).multilineTextAlignment(.leading)
                            Spacer()
                            if let picked, i == q.correctIndex {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    .accessibilityLabel(picked == i ? "Correct" : "Correct answer")
                            } else if picked == i {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                    .accessibilityLabel("Incorrect")
                            }
                        }
                        .padding(16)
                        .background(.background.secondary, in: .rect(cornerRadius: 16))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if picked != nil {
                    Button("Next") {
                        picked = nil
                        index += 1
                    }
                    .primaryAction()
                }
            }
            .padding()
        }
        .sensoryFeedback(.success, trigger: correct)
    }
}
