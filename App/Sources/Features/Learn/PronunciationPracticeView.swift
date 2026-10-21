import LanguifyKit
import SwiftData
import SwiftUI

/// Picks a word to practise: saved words first, then everyday starter words.
struct PronunciationListView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \VocabularyEntry.lastEncounteredAt, order: .reverse) private var entries: [VocabularyEntry]

    var body: some View {
        let language = services.preferences.language
        List {
            let mine = entries.filter { $0.languageCode == language.rawValue }
            if !mine.isEmpty {
                Section("Your words") {
                    ForEach(mine) { entry in
                        NavigationLink(value: PracticeTarget(entry: entry)) {
                            VocabularyRow(entry: entry)
                        }
                    }
                }
            }
            Section("Everyday words") {
                ForEach(StarterWords.words(for: language), id: \.self) { word in
                    NavigationLink(value: PracticeTarget(word: word)) {
                        PhraseView(nativeScript: word.nativeScript, transliteration: word.transliteration, english: word.english, size: .compact)
                    }
                }
            }
        }
        .navigationTitle("Say It Out Loud")
        .navigationDestination(for: PracticeTarget.self) { PronunciationPracticeView(target: $0) }
    }
}

struct PronunciationPracticeView: View {
    let target: PracticeTarget
    @Environment(AppServices.self) private var services
    @State private var recorder: UtteranceRecorder?
    @State private var result: PronunciationScorer.Result?

    var body: some View {
        let language = services.preferences.language
        ScrollView {
            VStack(spacing: 20) {
                Card {
                    PhraseView(nativeScript: target.nativeScript, transliteration: target.transliteration, english: target.english, size: .large) {
                        services.delivery.pronounce(target.speakable, language: language)
                    }
                    Button { services.delivery.pronounce(target.speakable, language: language, slow: true) } label: {
                        Label("Hear it slowly", systemImage: "tortoise")
                    }
                    .buttonStyle(.bordered)
                    if !services.delivery.hasVoice(for: language) {
                        Text("This iPhone has no \(language.displayName) voice installed, so playback may not sound right. Ask a family member to say it for you!")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let recorder {
                    RecordButton(recorder: recorder) { heard in
                        guard let heard else { return }
                        let scored = PronunciationScorer().score(target: target.transliteration, heard: heard.text)
                        result = scored
                        services.preferences.profile.record(.pronunciationAttempt(similarity: scored.similarity))
                    }
                    if let error = recorder.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                }

                if let result {
                    FeedbackCard(result: result)
                }

                Text("Feedback compares what Apple's on-device \(language.displayName) recogniser understood with the target word. It tells you whether you were understood, not a phoneme-by-phoneme score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if recorder == nil { recorder = UtteranceRecorder(services: services) } }
        .onDisappear { recorder?.cancel() }
    }
}

/// Tap to start, tap to stop. Shows real input levels while recording.
struct RecordButton: View {
    let recorder: UtteranceRecorder
    let onResult: (TranscriptSegment?) -> Void

    var body: some View {
        VStack(spacing: 12) {
            WaveformView(levels: recorder.levels, isActive: recorder.state == .recording)
                .frame(height: 44)
            Button {
                Task {
                    switch recorder.state {
                    case .idle: await recorder.start()
                    case .recording: onResult(await recorder.stopAndTranscribe())
                    case .transcribing: break
                    }
                }
            } label: {
                Label(label, systemImage: recorder.state == .recording ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(recorder.state == .recording ? .red : .accentColor)
            .disabled(recorder.state == .transcribing)
            .accessibilityIdentifier("record.button")
        }
    }

    private var label: String {
        switch recorder.state {
        case .idle: "Tap and say it"
        case .recording: "Done"
        case .transcribing: "Listening back\u{2026}"
        }
    }
}

private struct FeedbackCard: View {
    let result: PronunciationScorer.Result

    var body: some View {
        Card {
            Label(result.verdict.headline, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            if !result.heardText.isEmpty {
                LabeledContent("Languify heard", value: result.heardText)
            }
            if result.words.count > 1 {
                HStack {
                    ForEach(Array(result.words.enumerated()), id: \.offset) { _, word in
                        Text(word.target)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((word.matched ? Color.green : Color.orange).opacity(0.15), in: .capsule)
                            .accessibilityLabel("\(word.target), \(word.matched ? "understood" : "unclear")")
                    }
                }
            }
            Text(advice).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var symbol: String {
        switch result.verdict {
        case .recognized: "checkmark.seal.fill"
        case .close: "hand.thumbsup"
        case .different: "arrow.triangle.2.circlepath"
        case .nothingHeard: "ear.trianglebadge.exclamationmark"
        }
    }

    private var color: Color {
        switch result.verdict {
        case .recognized: .green
        case .close: .teal
        case .different, .nothingHeard: .orange
        }
    }

    private var advice: String {
        switch result.verdict {
        case .recognized: "Nice. Try using it in a sentence next time you talk with family."
        case .close: "Close. Listen again and match the vowel lengths; long vowels like aa and ee are held a little longer."
        case .different: "It was understood as a different word. Listen slowly, then try once more."
        case .nothingHeard: "Try again a little closer to the phone."
        }
    }
}
