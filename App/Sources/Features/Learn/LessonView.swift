import LanguifyKit
import SwiftUI

/// A short AI-generated lesson built from the learner's saved words and
/// weakest skill estimate.
struct LessonView: View {
    @Environment(AppServices.self) private var services
    @State private var lesson: Lesson?
    @State private var error: String?
    @State private var isLoading = false
    @State private var recorder: UtteranceRecorder?
    @State private var attempts: [String: String] = [:]

    var body: some View {
        let language = services.preferences.language
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView("Building your lesson\u{2026}").frame(maxWidth: .infinity).padding(.top, 60)
                } else if let lesson {
                    Text(lesson.title).font(.largeTitle.bold())
                    Text(lesson.goal).foregroundStyle(.secondary)
                    ForEach(Array(lesson.steps.enumerated()), id: \.offset) { i, step in
                        Card {
                            Text("Step \(i + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(step.prompt).font(.headline)
                            if let model = step.model {
                                PhraseView(nativeScript: model.nativeScript, transliteration: model.transliteration, english: model.english) {
                                    services.delivery.pronounce(model.nativeScript.isEmpty ? model.transliteration : model.nativeScript, language: language)
                                }
                            }
                            if let tip = step.tip { NoteRow(symbol: "lightbulb", text: tip) }
                            if step.kind != .explain, let recorder {
                                RecordButton(recorder: recorder) { heard in
                                    guard let heard else { return }
                                    attempts[step.id] = heard.text
                                    if let model = step.model {
                                        let score = PronunciationScorer().score(target: model.transliteration, heard: heard.text)
                                        services.preferences.profile.record(.pronunciationAttempt(similarity: score.similarity))
                                    }
                                }
                                if let attempt = attempts[step.id] {
                                    LabeledContent("You said", value: attempt).font(.subheadline)
                                }
                            }
                        }
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("Lesson unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if recorder == nil { recorder = UtteranceRecorder(services: services) }
            if lesson == nil { await load() }
        }
        .onDisappear { recorder?.cancel() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let language = services.preferences.language
        let entries = services.repository.entries(language: language)
        var words = entries.prefix(15).map { LessonWord(transliteration: $0.transliteration, english: $0.englishMeaning, context: $0.contextSentence) }
        if words.isEmpty {
            words = StarterWords.words(for: language).map { LessonWord(transliteration: $0.transliteration, english: $0.english, context: nil) }
        }
        let focus = services.preferences.profile.focusAreas.first(where: { $0 != .listening }) ?? .speaking
        do {
            lesson = try await services.api.lesson(LessonRequest(language: language, focus: focus, words: words, learner: services.preferences.learnerSnapshot(recentWords: [])))
        } catch let apiError as APIError {
            error = apiError.userMessage
        } catch {
            self.error = "Couldn't build a lesson right now."
        }
    }
}
