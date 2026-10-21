import LanguifyKit
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \VocabularyEntry.lastEncounteredAt, order: .reverse) private var entries: [VocabularyEntry]

    var body: some View {
        let language = services.preferences.language
        let mine = entries.filter { $0.languageCode == language.rawValue }
        let due = ReviewQueue.dueCount(in: mine.map(\.studyCard), now: Date())

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    listeningCard

                    if !services.suggestions.pending.isEmpty {
                        SuggestionsCard()
                    }

                    HStack(spacing: 12) {
                        StatTile(value: "\(mine.count)", label: "Words saved", symbol: "character.book.closed")
                        StatTile(value: "\(due)", label: "Ready to review", symbol: "rectangle.stack")
                    }

                    if due > 0 {
                        NavigationLink {
                            FlashcardSessionView()
                        } label: {
                            Label("Review \(due) word\(due == 1 ? "" : "s")", systemImage: "rectangle.stack")
                        }
                        .primaryAction()
                    }

                    if mine.isEmpty {
                        Card {
                            Label("Your journal fills itself", systemImage: "sparkles")
                                .font(.headline)
                            Text("Start listening before your next family conversation. Every word you ask about is saved here with the sentence it came from.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Recently learned")
                            ForEach(mine.prefix(5)) { entry in
                                NavigationLink {
                                    VocabularyDetailView(entry: entry)
                                } label: {
                                    Card(padding: 14) {
                                        HStack {
                                            PhraseView(nativeScript: entry.nativeScript, transliteration: entry.transliteration, english: entry.englishMeaning, size: .compact)
                                            StatusBadge(status: entry.status)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    NextStepCard()
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle(greeting(language))
        }
    }

    private var listeningCard: some View {
        let listening = services.listening
        return Card {
            HStack(spacing: 14) {
                Image(systemName: listening.state.isSessionActive ? "waveform" : "waveform.slash")
                    .font(.title)
                    .foregroundStyle(listening.state.isCapturing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .symbolEffect(.variableColor.iterative, isActive: listening.state.isCapturing)
                    .frame(width: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(listening.state.isSessionActive ? "Listening for \(services.preferences.language.displayName)" : "Ready when you are")
                        .font(.headline)
                    Text(listening.state.isSessionActive ? "Ask in the Rewind tab or with Siri." : "Start before a conversation. Only the last \(services.preferences.preferences.rewindDuration.label) are kept.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if listening.state.isSessionActive {
                Button("Open Live Rewind") { services.selectedTab = .rewind }
                    .secondaryAction()
            } else {
                Button {
                    Task {
                        await listening.start()
                        if listening.state.isCapturing { services.selectedTab = .rewind }
                    }
                } label: {
                    Label("Start Listening", systemImage: "waveform")
                }
                .primaryAction()
                .accessibilityIdentifier("home.start")
            }
        }
    }

    private func greeting(_ language: HeritageLanguage) -> String {
        language.configuration.sampleGreetingTransliteration.capitalized
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var body: some View {
        Card(padding: 14) {
            Image(systemName: symbol).foregroundStyle(.tint).accessibilityHidden(true)
            Text(value).font(.title.weight(.semibold)).monospacedDigit()
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Recommends one next learning action from the weakest skill estimate.
private struct NextStepCard: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let focus = services.preferences.profile.focusAreas.first ?? .speaking
        Card {
            HStack {
                Text("Suggested next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                EstimateLabel()
            }
            Text(title(focus)).font(.headline)
            Text(detail(focus)).font(.subheadline).foregroundStyle(.secondary)
            Button("Go to Learn") { services.selectedTab = .learn }
                .buttonStyle(.bordered)
        }
    }

    private func title(_ d: SkillDimension) -> String {
        switch d {
        case .speaking, .sentenceConstruction: "Practise a short conversation"
        case .pronunciation: "Practise saying your saved words"
        case .vocabulary: "Review your words"
        case .listening: "Take the listening quiz"
        case .grammar: "Try a lesson on sentence patterns"
        }
    }

    private func detail(_ d: SkillDimension) -> String {
        "\(d.label) looks like your biggest opportunity right now, based on your practice so far."
    }
}
