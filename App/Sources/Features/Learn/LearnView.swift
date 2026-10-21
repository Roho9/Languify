import LanguifyKit
import SwiftData
import SwiftUI

struct LearnView: View {
    @Environment(AppServices.self) private var services
    @Query private var entries: [VocabularyEntry]
    @State private var showPaywall = false

    var body: some View {
        let language = services.preferences.language
        let mine = entries.filter { $0.languageCode == language.rawValue }
        let due = ReviewQueue.dueCount(in: mine.map(\.studyCard), now: Date())
        let resolver = services.subscriptions.resolver

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    SectionHeader(title: "From your conversations", subtitle: "Built from the \(mine.count) words you've saved.")
                    LearnLink(title: "Flashcards", detail: due > 0 ? "\(due) ready to review" : "Nothing due. Keep listening!", symbol: "rectangle.stack", locked: false) {
                        FlashcardSessionView()
                    }
                    LearnLink(title: "Quiz", detail: mine.count >= 4 ? "Meaning, recall and context questions" : "Save at least 4 words to unlock", symbol: "checklist", locked: false) {
                        QuizView()
                    }
                    LearnLink(title: "Say it out loud", detail: "Pronunciation practice with on-device feedback", symbol: "mic", locked: !resolver.has(.pronunciationCoaching)) {
                        PronunciationListView()
                    }

                    SectionHeader(title: "Speaking practice", subtitle: "Get comfortable replying instead of switching to English.")
                        .padding(.top, 8)
                    gated(.conversationPractice) {
                        LearnLink(title: "Conversation practice", detail: "Talk with an AI partner in everyday family situations", symbol: "bubble.left.and.bubble.right", locked: !resolver.has(.conversationPractice)) {
                            ConversationScenarioList()
                        }
                    }
                    gated(.personalizedLessons) {
                        LearnLink(title: "Today's lesson", detail: "A five-minute lesson focused on your weakest skill", symbol: "sparkles", locked: !resolver.has(.personalizedLessons)) {
                            LessonView()
                        }
                    }

                    SectionHeader(title: "Your progress").padding(.top, 8)
                    LearnLink(title: "Skills", detail: "Estimated from practice, plus any assessment you've taken", symbol: "chart.bar", locked: false) {
                        InsightsView()
                    }
                    LearnLink(title: "Quick check", detail: "Optional 3-minute listening and speaking check", symbol: "gauge.with.dots.needle.33percent", locked: false) {
                        AssessmentView()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Learn")
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    /// Locked Premium items open the paywall instead of navigating.
    @ViewBuilder
    private func gated<Content: View>(_ feature: Feature, @ViewBuilder content: () -> Content) -> some View {
        if services.subscriptions.resolver.has(feature) {
            content()
        } else {
            Button { showPaywall = true } label: {
                LearnRow(title: feature == .conversationPractice ? "Conversation practice" : "Today's lesson",
                         detail: "Premium", symbol: feature == .conversationPractice ? "bubble.left.and.bubble.right" : "sparkles", locked: true)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LearnLink<Destination: View>: View {
    let title: String
    let detail: String
    let symbol: String
    let locked: Bool
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            LearnRow(title: title, detail: detail, symbol: symbol, locked: locked)
        }
        .buttonStyle(.plain)
    }
}

private struct LearnRow: View {
    let title: String
    let detail: String
    let symbol: String
    let locked: Bool

    var body: some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(locked ? "Premium feature" : "")
    }
}
