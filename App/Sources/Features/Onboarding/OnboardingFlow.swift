import AVFoundation
import LanguifyKit
import SwiftUI

/// First-run setup for receptive bilinguals. No account is required.
/// The privacy model is explained before the microphone permission prompt.
struct OnboardingFlow: View {
    @Environment(AppServices.self) private var services
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, language, abilities, goals, display, responses, privacy, setup
    }

    var body: some View {
        @Bindable var prefs = services.preferences
        VStack(spacing: 0) {
            if step != .welcome {
                ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .accessibilityLabel("Step \(step.rawValue) of \(Step.allCases.count - 1)")
            }
            ScrollView {
                Group {
                    switch step {
                    case .welcome: WelcomeStep()
                    case .language: LanguageStep(language: $prefs.preferences.language)
                    case .abilities: AbilitiesStep(skills: $prefs.preferences.skills, rating: $prefs.preferences.selfRating)
                    case .goals: GoalsStep(goals: $prefs.preferences.goals)
                    case .display: DisplayStep(display: $prefs.preferences.scriptDisplay, showNative: $prefs.preferences.showNativeScript)
                    case .responses: ResponseStep(mode: $prefs.preferences.responseMode, duration: $prefs.preferences.rewindDuration)
                    case .privacy: PrivacyStep(cloudConsent: $prefs.preferences.cloudProcessingConsent)
                    case .setup: SetupStep()
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .animation(.smooth, value: step)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") { move(-1) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            Button(step == .setup ? "Start using Languify" : step == .welcome ? "Get started" : "Continue") {
                if step == .setup {
                    services.preferences.completeOnboarding()
                } else {
                    move(1)
                }
            }
            .primaryAction()
            .disabled(step == .goals && services.preferences.preferences.goals.isEmpty)
            .accessibilityIdentifier("onboarding.continue")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(
                symbol: "bubble.left.and.text.bubble.right",
                title: "You already understand more than you think.",
                subtitle: "Languify helps you turn the Tamil or Malayalam you grew up hearing into words you can say."
            )
            Card {
                Label("Ask about a word right after you hear it, without stopping the conversation.", systemImage: "waveform.badge.magnifyingglass")
                Label("Every word you ask about becomes part of your own vocabulary journal.", systemImage: "character.book.closed")
                Label("Practise speaking with lessons built from your real conversations.", systemImage: "mic")
            }
            .font(.body)
            Text("No account needed.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct LanguageStep: View {
    @Binding var language: HeritageLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(symbol: "globe.asia.australia", title: "Which language did you grow up hearing?", subtitle: "You can change this later in Settings.")
            ForEach(HeritageLanguage.allCases) { lang in
                Button {
                    language = lang
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(lang.displayName).font(.title3.weight(.semibold))
                            Text(lang.configuration.nativeName).font(.title3)
                        }
                        Spacer()
                        Image(systemName: language == lang ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(language == lang ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                    .padding(18)
                    .background(.background.secondary, in: .rect(cornerRadius: 20))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(language == lang ? .isSelected : [])
                .accessibilityIdentifier("language.\(lang.rawValue)")
            }
        }
    }
}

private struct AbilitiesStep: View {
    @Binding var skills: Set<SkillFocus>
    @Binding var rating: SelfRating

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(symbol: "ear.and.waveform", title: "How do you use the language today?", subtitle: "Select all that apply. Understanding it well and reading it are different skills, and that's normal.")
            ForEach(SkillFocus.allCases) { skill in
                Toggle(skill.label, isOn: Binding(
                    get: { skills.contains(skill) },
                    set: { if $0 { skills.insert(skill) } else { skills.remove(skill) } }
                ))
                .toggleStyle(.switch)
            }
            Divider()
            RatingRow(title: "Understanding", detail: "How much of a family conversation you follow", value: $rating.comprehension)
            RatingRow(title: "Speaking", detail: "How easily you can reply in the language", value: $rating.speaking)
            RatingRow(title: "Reading the script", detail: "Optional. Speaking practice never requires it", value: $rating.reading)
        }
    }
}

private struct RatingRow: View {
    let title: String
    let detail: String
    @Binding var value: Int
    private let labels = ["Very little", "Some", "About half", "Most", "Nearly all"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(labels[value - 1]).foregroundStyle(.secondary)
            }
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: 1...5, step: 1)
                .accessibilityValue(labels[value - 1])
                .accessibilityLabel(title)
        }
    }
}

private struct GoalsStep: View {
    @Binding var goals: Set<LearningGoal>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "target", title: "What would you like to do?", subtitle: "Languify shapes your practice around these.")
            ForEach(LearningGoal.allCases) { goal in
                let selected = goals.contains(goal)
                Button {
                    if selected { goals.remove(goal) } else { goals.insert(goal) }
                } label: {
                    HStack {
                        Text(goal.label)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                    .padding(16)
                    .background(.background.secondary, in: .rect(cornerRadius: 18))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct DisplayStep: View {
    @Binding var display: ScriptDisplay
    @Binding var showNative: Bool
    @Environment(AppServices.self) private var services

    var body: some View {
        let config = services.preferences.language.configuration
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(symbol: "textformat", title: "How should words look?", subtitle: "Transliteration spells words in English letters so you can say them without reading \(config.scriptName).")
            Picker("Show first", selection: $display) {
                ForEach(ScriptDisplay.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Toggle("Show \(config.scriptName)", isOn: $showNative)
            Card {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                PhraseView(nativeScript: config.sampleGreetingNative, transliteration: config.sampleGreetingTransliteration, english: "hello")
            }
        }
    }
}

private struct ResponseStep: View {
    @Binding var mode: ResponseMode
    @Binding var duration: RewindDuration

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(symbol: "airpods.pro", title: "How should Languify answer?", subtitle: "During a conversation, short answers can play privately in your AirPods.")
            ForEach(ResponseMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label).font(.headline)
                            Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(mode == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                    .padding(16)
                    .background(.background.secondary, in: .rect(cornerRadius: 18))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Rewind window").font(.headline)
                Text("How much recent audio Languify keeps in memory. Older audio is erased continuously.").font(.footnote).foregroundStyle(.secondary)
                Picker("Rewind window", selection: $duration) {
                    ForEach(RewindDuration.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct PrivacyStep: View {
    @Binding var cloudConsent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "lock.shield", title: "Your conversations stay yours", subtitle: "Here's exactly what happens to audio.")
            Card {
                Label("Languify only listens after you start a session, and iOS shows the microphone indicator the whole time.", systemImage: "mic.badge.plus")
                Label("Only the last 30 seconds to 2 minutes are kept, in memory. Older audio is erased continuously, and everything is erased when you stop.", systemImage: "clock.arrow.circlepath")
                Label("Speech is turned into text on your iPhone. Audio is never uploaded or saved.", systemImage: "iphone")
                Label("When you ask a question, only the text of that short window is sent to Languify's AI service to explain it. Languify doesn't store it, and it isn't used to train AI models.", systemImage: "text.bubble")
            }
            .font(.subheadline)
            Toggle(isOn: $cloudConsent) {
                VStack(alignment: .leading) {
                    Text("Allow AI explanations").font(.headline)
                    Text("Sends the transcribed text of the rewind window when you ask. You can change this any time.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("onboarding.cloudConsent")
            RecordingConsentNote()
        }
    }
}

struct RecordingConsentNote: View {
    var body: some View {
        Card {
            Label("Let people know", systemImage: "person.2.wave.2")
                .font(.headline)
            Text("Languify processes what other people say. Tell the people you're talking with that you use a listening app to help with the language, and follow the recording laws where you live. Some places require everyone's consent, even for audio that's never saved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SetupStep: View {
    @Environment(AppServices.self) private var services
    @State private var micStatus = AVAudioApplication.shared.recordPermission

    var body: some View {
        let language = services.preferences.language
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(symbol: "checklist", title: "Two quick setup steps", subtitle: "Both happen on your iPhone.")
            Card {
                HStack {
                    Label("Microphone", systemImage: "mic")
                        .font(.headline)
                    Spacer()
                    switch micStatus {
                    case .granted:
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .denied:
                        Button("Open Settings") { openSettings() }
                    default:
                        Button("Allow") {
                            Task {
                                _ = await AVAudioApplication.requestRecordPermission()
                                micStatus = AVAudioApplication.shared.recordPermission
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("onboarding.allowMic")
                    }
                }
                Text("Needed to listen during sessions you start.").font(.footnote).foregroundStyle(.secondary)
            }
            Card {
                Label("Speech recognition", systemImage: "waveform")
                    .font(.headline)
                ForEach(services.speechModels.requiredLocales(for: language), id: \.self) { id in
                    ModelStatusRow(localeIdentifier: id)
                }
                Text("Downloads Apple's on-device \(language.displayName) and Indian English speech models so transcription never needs the internet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("You can finish later; Languify will remind you before your first session.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .task { await services.speechModels.refresh(for: language) }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

struct ModelStatusRow: View {
    let localeIdentifier: String
    @Environment(AppServices.self) private var services

    var body: some View {
        let state = services.speechModels.state(for: localeIdentifier)
        HStack {
            Text(Locale.current.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier)
            Spacer()
            switch state {
            case .installed:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .downloading(let progress):
                ProgressView(value: progress).frame(width: 90)
            case .unsupported:
                Text("Not supported on this device").foregroundStyle(.secondary)
            case .failed:
                Button("Retry") { Task { await services.speechModels.install(localeIdentifier: localeIdentifier) } }
            case .notInstalled, .unknown:
                Button("Download") { Task { await services.speechModels.install(localeIdentifier: localeIdentifier) } }
                    .buttonStyle(.bordered)
            }
        }
        .font(.subheadline)
    }
}
