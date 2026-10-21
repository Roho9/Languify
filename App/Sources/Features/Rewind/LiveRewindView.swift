import LanguifyKit
import SwiftUI

struct LiveRewindView: View {
    @Environment(AppServices.self) private var services
    @State private var outcome: RewindOutcome?
    @State private var showAskSheet = false
    @State private var askDraft = AskDraft()
    @State private var showPaywall = false
    @Namespace private var glass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sessionCard
                    if services.listening.state.isSessionActive || outcome != nil {
                        questionControls
                    }
                    if services.rewind.isWorking {
                        ProcessingCard(stage: services.rewind.stage ?? "Working")
                    }
                    if let outcome, !services.rewind.isWorking {
                        OutcomeView(outcome: outcome, onAsk: ask, onUpgrade: { showPaywall = true }, onRefine: { draft in
                            askDraft = draft
                            showAskSheet = true
                        })
                    }
                    if !services.suggestions.pending.isEmpty {
                        SuggestionsCard()
                    }
                    recentAnswers
                    if !services.listening.state.isSessionActive {
                        SiriTipCard()
                        RecordingConsentNote()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Live Rewind")
            .sheet(isPresented: $showAskSheet) {
                AskSheet(draft: askDraft) { query in
                    showAskSheet = false
                    ask(query)
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onChange(of: services.preferences.preferences.rewindDuration) { _, new in
                services.listening.applyRewindDuration(new)
            }
        }
    }

    // MARK: Session

    private var sessionCard: some View {
        let listening = services.listening
        @Bindable var prefs = services.preferences
        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle(listening.state)).font(.title2.weight(.semibold))
                    Text(statusDetail(listening)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if listening.state.isCapturing {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Microphone on")
                }
            }
            WaveformView(levels: listening.levels, isActive: listening.state.isCapturing)
                .frame(height: 64)
                .padding(.vertical, 4)

            if listening.state.isSessionActive {
                // The buffer is not observable, so sample it once a second while visible.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Gauge(value: min(listening.bufferedSeconds, listening.rewindSeconds), in: 0...listening.rewindSeconds) {
                        Text("Rewind buffer")
                    } currentValueLabel: {
                        Text("\(Int(listening.bufferedSeconds))s of \(Int(listening.rewindSeconds))s kept")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Picker("Rewind window", selection: $prefs.preferences.rewindDuration) {
                ForEach(RewindDuration.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if listening.state.isSessionActive {
                        if listening.state == .paused {
                            Button { listening.resume() } label: { Label("Resume", systemImage: "play.fill") }
                                .secondaryAction()
                                .glassEffectID("pause", in: glass)
                        } else if listening.state.isCapturing {
                            Button { listening.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                                .secondaryAction()
                                .glassEffectID("pause", in: glass)
                        }
                        Button(role: .destructive) {
                            Task { await listening.stop() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .primaryAction()
                        .tint(.red)
                        .glassEffectID("main", in: glass)
                        .accessibilityIdentifier("rewind.stop")
                    } else {
                        Button {
                            Task { await listening.start() }
                        } label: {
                            Label("Start Listening", systemImage: "waveform")
                        }
                        .primaryAction()
                        .glassEffectID("main", in: glass)
                        .disabled(listening.state == .requestingPermission || listening.state == .starting)
                        .accessibilityIdentifier("rewind.start")
                    }
                }
            }
            if let error = listening.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if !services.speechModels.isReady(for: services.preferences.language) {
                ModelMissingNote()
            }
        }
        .sensoryFeedback(.start, trigger: listening.state == .listening)
    }

    private var questionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ask about what you just heard")
            GlassEffectContainer(spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach([RewindQuestionKind.word, .sentence, .gist, .respond, .expression, .grammar], id: \.self) { kind in
                        Button {
                            ask(RewindQuery(question: question(for: kind), kind: kind))
                        } label: {
                            Label(kind.label, systemImage: kind.symbolName)
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.glass)
                        .disabled(services.rewind.isWorking)
                        .accessibilityIdentifier("rewind.ask.\(kind.rawValue)")
                    }
                }
            }
            Button {
                askDraft = AskDraft()
                showAskSheet = true
            } label: {
                Label("Ask something else\u{2026}", systemImage: "text.bubble")
            }
            .buttonStyle(.borderless)
            .disabled(services.rewind.isWorking)
        }
    }

    @ViewBuilder
    private var recentAnswers: some View {
        let answers = services.rewind.recentAnswers
        if !answers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "This session", subtitle: "Cleared when you stop listening. Words are saved to your journal.")
                ForEach(answers) { answer in
                    NavigationLink {
                        ExplanationDetailView(answer: answer)
                    } label: {
                        CompactAnswerRow(answer: answer)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Actions

    private func ask(_ query: RewindQuery) {
        var query = query
        query.askedAt = ProcessInfo.processInfo.systemUptime
        Task {
            outcome = await services.rewind.ask(query)
        }
    }

    private func question(for kind: RewindQuestionKind) -> String {
        kind == .respond ? "How would I respond in \(services.preferences.language.displayName)?" : kind.defaultQuestion
    }

    private func statusTitle(_ state: ListeningSessionState) -> String {
        switch state {
        case .idle: "Not listening"
        case .requestingPermission: "Waiting for permission"
        case .starting: "Starting\u{2026}"
        case .listening: "Listening"
        case .processing: "Listening \u{00B7} thinking"
        case .paused: "Paused"
        case .interrupted: "Microphone in use by iOS"
        case .failed: "Couldn't start"
        case .stopping: "Stopping\u{2026}"
        }
    }

    private func statusDetail(_ listening: ListeningSessionManager) -> String {
        let route = "Mic: \(services.audioSession.inputName) \u{00B7} Answers: \(services.audioSession.outputName)"
        switch listening.state {
        case .idle, .failed: return "Start a session before a conversation. Only the last \(services.preferences.preferences.rewindDuration.label) are kept."
        case .interrupted: return "Siri or a call has the mic. What was said before is still available."
        default: return route
        }
    }
}

struct AskDraft: Equatable {
    var question = ""
    var soundsLike = ""
    var context = ""
    var reuse: RewindQuery?
}

private struct ProcessingCard: View {
    let stage: String
    var body: some View {
        Card {
            HStack(spacing: 12) {
                ProgressView()
                Text(stage).font(.headline)
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ModelMissingNote: View {
    @Environment(AppServices.self) private var services
    var body: some View {
        let language = services.preferences.language
        VStack(alignment: .leading, spacing: 8) {
            Label("The \(language.displayName) speech model isn't downloaded yet. Questions need it.", systemImage: "arrow.down.circle")
                .font(.footnote)
            ForEach(services.speechModels.requiredLocales(for: language), id: \.self) { ModelStatusRow(localeIdentifier: $0) }
        }
        .foregroundStyle(.secondary)
    }
}

private struct SiriTipCard: View {
    var body: some View {
        Card {
            Label("Hands-free with Siri and AirPods", systemImage: "airpods.pro")
                .font(.headline)
            Text("Start a session, then lock your phone. When you hear something unfamiliar, say:")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("\u{201C}Siri, ask Languify what that word meant\u{201D}")
                Text("\u{201C}Siri, ask Languify what that sentence meant\u{201D}")
                Text("\u{201C}Siri, ask Languify how to respond\u{201D}")
            }
            .font(.subheadline.italic())
            Text("Keep your iPhone on the table if you can: its microphone hears the room better than a pocket or AirPods.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct CompactAnswerRow: View {
    let answer: RewindAnswer
    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .top) {
                Image(systemName: answer.query.kind.symbolName).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(answer.query.question).font(.caption).foregroundStyle(.secondary)
                    Text(answer.explanation.spokenSummary).font(.subheadline).lineLimit(3)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
