import LanguifyKit
import SwiftUI

struct ConversationScenario: Hashable, Identifiable {
    let id: String
    let title: String
    let symbol: String
    let prompt: String

    static let all: [ConversationScenario] = [
        .init(id: "parents", title: "Talking with your parents", symbol: "figure.2.and.child.holdinghands", prompt: "A parent asks the learner how their day went and what they ate"),
        .init(id: "grandparents", title: "Calling your grandparents", symbol: "phone", prompt: "A grandparent on a phone call asks about the learner's health, studies and when they will visit"),
        .init(id: "gathering", title: "Family gathering", symbol: "person.3", prompt: "An aunt or uncle at a family function asks what the learner is doing these days"),
        .init(id: "food", title: "Ordering food", symbol: "fork.knife", prompt: "Ordering at a small restaurant or tea shop in the home town"),
        .init(id: "day", title: "Describing your day", symbol: "sun.max", prompt: "Telling a family member what the learner did today, in order"),
        .init(id: "school", title: "School or work", symbol: "briefcase", prompt: "Explaining what the learner studies or works on to a relative who is curious"),
        .init(id: "opinion", title: "Sharing an opinion", symbol: "bubble.left.and.exclamationmark.bubble.right", prompt: "A family member asks what the learner thinks about a film they all watched"),
        .init(id: "festival", title: "Festivals and traditions", symbol: "sparkles", prompt: "Talking about preparations for a festival like Pongal or Onam"),
    ]
}

struct ConversationScenarioList: View {
    var body: some View {
        List(ConversationScenario.all) { scenario in
            NavigationLink(value: scenario) {
                Label(scenario.title, systemImage: scenario.symbol)
            }
        }
        .navigationTitle("Conversation")
        .navigationDestination(for: ConversationScenario.self) { ConversationPracticeView(scenario: $0) }
    }
}

/// Spoken conversation with the AI tutor. The learner's speech is transcribed
/// on device; only the text goes to the tutor.
struct ConversationPracticeView: View {
    let scenario: ConversationScenario
    @Environment(AppServices.self) private var services
    @State private var messages: [TutorMessage] = []
    @State private var feedback: [UUID: TutorTurnResponse] = [:]
    @State private var recorder: UtteranceRecorder?
    @State private var isThinking = false
    @State private var error: String?
    @State private var typed = ""

    var body: some View {
        let language = services.preferences.language
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, feedback: feedback[message.id], language: language)
                                .id(message.id)
                        }
                        if isThinking {
                            ProgressView().padding()
                        }
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            VStack(spacing: 8) {
                if let recorder {
                    RecordButton(recorder: recorder) { heard in
                        guard let heard, !heard.text.isEmpty else { return }
                        send(heard.text, confidence: heard.confidence)
                    }
                }
                HStack {
                    TextField("Or type in \(language.displayName) or English letters", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { sendTyped() }
                    Button("Send", action: sendTyped).disabled(typed.nilIfBlank == nil || isThinking)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if recorder == nil { recorder = UtteranceRecorder(services: services) }
            if messages.isEmpty { send("", confidence: nil) }
        }
        .onDisappear { recorder?.cancel() }
    }

    private func sendTyped() {
        guard let text = typed.nilIfBlank else { return }
        typed = ""
        send(text, confidence: nil)
    }

    private func send(_ utterance: String, confidence: Double?) {
        let history = messages
        var learnerMessage: TutorMessage?
        if !utterance.isEmpty {
            let message = TutorMessage(role: .learner, transliteration: utterance)
            messages.append(message)
            learnerMessage = message
        }
        isThinking = true
        error = nil
        Task {
            defer { isThinking = false }
            let request = TutorTurnRequest(
                language: services.preferences.language,
                scenario: scenario.prompt,
                history: history,
                learnerUtterance: utterance,
                learnerUtteranceConfidence: confidence,
                learner: services.preferences.learnerSnapshot(recentWords: services.repository.recentTransliterations(language: services.preferences.language))
            )
            do {
                let response = try await services.api.tutorTurn(request)
                let reply = TutorMessage(role: .tutor, transliteration: response.reply.transliteration, nativeScript: response.reply.nativeScript, english: response.reply.english)
                if let learnerMessage {
                    feedback[learnerMessage.id] = response
                    services.preferences.profile.record(.tutorTurn(fluency: response.assessment.fluency, grammar: response.assessment.grammar, completeSentence: response.assessment.completeSentence))
                }
                messages.append(reply)
                services.delivery.pronounce(reply.nativeScript.isEmpty ? reply.transliteration : reply.nativeScript, language: services.preferences.language)
            } catch let apiError as APIError {
                error = apiError.userMessage
            } catch {
                self.error = "The tutor didn't respond. Try again."
            }
        }
    }
}

private struct MessageBubble: View {
    let message: TutorMessage
    let feedback: TutorTurnResponse?
    let language: HeritageLanguage
    @Environment(AppServices.self) private var services

    var body: some View {
        let isTutor = message.role == .tutor
        VStack(alignment: isTutor ? .leading : .trailing, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                if isTutor {
                    PhraseView(nativeScript: message.nativeScript, transliteration: message.transliteration, english: message.english, size: .compact) {
                        services.delivery.pronounce(message.nativeScript.isEmpty ? message.transliteration : message.nativeScript, language: language)
                    }
                } else {
                    Text(message.transliteration)
                }
            }
            .padding(12)
            .background(isTutor ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.tint.opacity(0.18)), in: .rect(cornerRadius: 18))

            if let feedback {
                if let correction = feedback.correction {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("More natural", systemImage: "wand.and.stars").font(.caption.weight(.semibold))
                        Text(correction.natural.transliteration).font(.subheadline.weight(.medium))
                        Text(correction.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 14))
                }
                Text(feedback.encouragement).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: isTutor ? .leading : .trailing)
    }
}
