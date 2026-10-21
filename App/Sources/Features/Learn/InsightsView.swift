import Charts
import LanguifyKit
import SwiftData
import SwiftUI

/// Skill profile. Estimates (from everyday practice) and measured results
/// (from the optional assessment) are always shown separately.
struct InsightsView: View {
    @Environment(AppServices.self) private var services
    @Query private var entries: [VocabularyEntry]
    @Query private var reviews: [ReviewRecord]

    var body: some View {
        let profile = services.preferences.profile
        let language = services.preferences.language
        let mine = entries.filter { $0.languageCode == language.rawValue }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    SectionHeader(title: "Skills", subtitle: "Bars are estimates from your practice. Diamonds are results from the Quick check.")
                    Chart {
                        ForEach(SkillDimension.allCases) { dimension in
                            let score = profile.score(dimension)
                            BarMark(x: .value("Estimate", score.estimated), y: .value("Skill", dimension.label))
                                .foregroundStyle(.tint.opacity(0.7))
                                .accessibilityLabel(dimension.label)
                                .accessibilityValue("Estimated \(Int(score.estimated)) of 100\(score.verified.map { ", measured \(Int($0))" } ?? "")")
                            if let verified = score.verified {
                                PointMark(x: .value("Measured", verified), y: .value("Skill", dimension.label))
                                    .symbol(.diamond)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .chartXScale(domain: 0...100)
                    .frame(height: 260)
                    HStack {
                        EstimateLabel()
                        Spacer()
                        Text("Evidence: \(profile.scores.values.map(\.evidenceCount).reduce(0, +)) practice events")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    StatCard(value: "\(mine.count)", label: "Words saved")
                    StatCard(value: "\(mine.filter { $0.status == .mastered }.count)", label: "Mastered")
                    StatCard(value: "\(reviews.count)", label: "Reviews")
                }

                Card {
                    SectionHeader(title: "Focus next")
                    ForEach(profile.focusAreas.prefix(2)) { dimension in
                        Label("\(dimension.label): \(advice(dimension))", systemImage: "arrow.forward.circle")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func advice(_ d: SkillDimension) -> String {
        switch d {
        case .listening: "keep asking about unfamiliar words during conversations"
        case .speaking: "try a conversation practice scenario"
        case .vocabulary: "review your flashcards daily"
        case .pronunciation: "say your saved words out loud"
        case .sentenceConstruction: "answer in full sentences in practice"
        case .grammar: "take a lesson focused on sentence patterns"
        }
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    var body: some View {
        Card(padding: 14) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Optional short check that measures listening and speaking separately.
/// Reading ability is never assumed from either.
struct AssessmentView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .intro
    @State private var listeningQuestions: [QuizQuestion] = []
    @State private var speakingWords: [StarterWords.Word] = []
    @State private var index = 0
    @State private var listeningCorrect = 0
    @State private var speakingScores: [Double] = []
    @State private var picked: Int?
    @State private var recorder: UtteranceRecorder?

    enum Phase { case intro, listening, speaking, done }

    var body: some View {
        let language = services.preferences.language
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch phase {
                case .intro:
                    Text("Quick check").font(.largeTitle.bold())
                    Text("Two short parts: listen to words and pick their meaning, then say a few everyday words. It measures listening and speaking separately and doesn't involve reading the script.")
                    if !services.delivery.hasVoice(for: language) {
                        Label("This iPhone has no \(language.displayName) voice, so the listening part is skipped.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Begin") { begin() }.primaryAction()

                case .listening:
                    let q = listeningQuestions[index]
                    Text("Listening \(index + 1) of \(listeningQuestions.count)").font(.caption).foregroundStyle(.secondary)
                    Button {
                        services.delivery.pronounce(q.audioText ?? "", language: language)
                    } label: {
                        Label("Play word", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                        Button {
                            guard picked == nil else { return }
                            picked = i
                            if i == q.correctIndex { listeningCorrect += 1 }
                        } label: {
                            HStack {
                                Text(option)
                                Spacer()
                                if picked != nil, i == q.correctIndex { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                            .padding(14)
                            .background(.background.secondary, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    if picked != nil {
                        Button("Next") { nextListening() }.primaryAction()
                    }

                case .speaking:
                    let word = speakingWords[index]
                    Text("Speaking \(index + 1) of \(speakingWords.count)").font(.caption).foregroundStyle(.secondary)
                    Text("How do you say \u{201C}\(word.english)\u{201D}?").font(.title2.weight(.semibold))
                    if let recorder {
                        RecordButton(recorder: recorder) { heard in
                            let score = PronunciationScorer().score(target: word.transliteration, heard: heard?.text ?? "")
                            speakingScores.append(score.similarity)
                            nextSpeaking()
                        }
                    }
                    Button("I don't know this one") {
                        speakingScores.append(0)
                        nextSpeaking()
                    }
                    .buttonStyle(.borderless)

                case .done:
                    Text("Done").font(.largeTitle.bold())
                    if !listeningQuestions.isEmpty {
                        LabeledContent("Listening", value: "\(listeningCorrect) of \(listeningQuestions.count)")
                    }
                    LabeledContent("Speaking", value: "\(Int(speakingAverage * 100))% understood")
                    Text("Saved as measured results. They appear as diamonds in Progress, next to your everyday estimates.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Close") { dismiss() }.primaryAction()
                }
            }
            .padding()
        }
        .navigationTitle("Quick Check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if recorder == nil { recorder = UtteranceRecorder(services: services) } }
        .onDisappear { recorder?.cancel() }
    }

    private var speakingAverage: Double {
        speakingScores.isEmpty ? 0 : speakingScores.reduce(0, +) / Double(speakingScores.count)
    }

    private func begin() {
        let language = services.preferences.language
        let words = StarterWords.words(for: language)
        speakingWords = Array(words.shuffled().prefix(5))
        if services.delivery.hasVoice(for: language) {
            let cards = words.map { StudyCard(nativeScript: $0.nativeScript, transliteration: $0.transliteration, englishMeaning: $0.english) }
            var rng = SystemRandomNumberGenerator()
            listeningQuestions = cards.shuffled(using: &rng).prefix(5).compactMap {
                QuizGenerator().makeQuestion(type: .listening, card: $0, pool: cards, rng: &rng)
            }
        }
        index = 0
        phase = listeningQuestions.isEmpty ? .speaking : .listening
    }

    private func nextListening() {
        picked = nil
        if index + 1 < listeningQuestions.count {
            index += 1
        } else {
            services.preferences.profile.recordAssessment(.listening, result: Double(listeningCorrect) / Double(listeningQuestions.count) * 100, at: Date())
            index = 0
            phase = .speaking
        }
    }

    private func nextSpeaking() {
        if index + 1 < speakingWords.count {
            index += 1
        } else {
            let pct = speakingAverage * 100
            services.preferences.profile.recordAssessment(.pronunciation, result: pct, at: Date())
            services.preferences.profile.recordAssessment(.speaking, result: pct, at: Date())
            phase = .done
        }
    }
}
