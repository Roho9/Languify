import LanguifyKit
import SwiftUI

// MARK: - Content surfaces

/// Grouped content container. Content uses solid materials; Liquid Glass is
/// reserved for controls and navigation that float above content, per HIG.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Phrase display

/// Shows a word or phrase in the learner's preferred order of native script,
/// transliteration and English, with a pronunciation button.
struct PhraseView: View {
    let nativeScript: String
    let transliteration: String
    let english: String
    var size: Size = .regular
    var onPlay: (() -> Void)?

    enum Size { case large, regular, compact }

    @Environment(AppServices.self) private var services

    var body: some View {
        let prefs = services.preferences.preferences
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines(prefs).enumerated()), id: \.offset) { index, line in
                    Text(line.text)
                        .font(index == 0 ? primaryFont : secondaryFont)
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel(line.accessibility)
                }
            }
            Spacer(minLength: 0)
            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(size == .large ? .title2 : .body)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play pronunciation")
            }
        }
    }

    private struct Line { let text: String; let accessibility: String }

    private func lines(_ prefs: UserPreferences) -> [Line] {
        let native = prefs.showNativeScript && !nativeScript.isEmpty ? Line(text: nativeScript, accessibility: "\(nativeScript), in \(services.preferences.language.configuration.scriptName)") : nil
        let translit = transliteration.isEmpty ? nil : Line(text: transliteration, accessibility: transliteration)
        let eng = english.isEmpty ? nil : Line(text: english, accessibility: "Meaning: \(english)")
        let ordered: [Line?] = switch prefs.scriptDisplay {
        case .transliterationFirst: [translit, native, eng]
        case .nativeScriptFirst: [native, translit, eng]
        case .englishFirst: [eng, translit, native]
        }
        return ordered.compactMap { $0 }
    }

    private var primaryFont: Font {
        switch size {
        case .large: .largeTitle.weight(.semibold)
        case .regular: .title3.weight(.semibold)
        case .compact: .headline
        }
    }

    private var secondaryFont: Font {
        switch size {
        case .large: .title3
        case .regular: .body
        case .compact: .subheadline
        }
    }
}

// MARK: - Badges

struct StatusBadge: View {
    let status: LearningStatus
    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
    private var color: Color {
        switch status {
        case .new: .blue
        case .learning: .orange
        case .reviewing: .teal
        case .mastered: .green
        }
    }
}

struct EstimateLabel: View {
    var body: some View {
        Label("Estimate", systemImage: "chart.line.uptrend.xyaxis")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Estimated from your practice, not a test result")
    }
}

// MARK: - Waveform

/// Live input level bars. Driven only by real microphone levels, so it is flat
/// whenever Languify is not actually capturing audio.
struct WaveformView: View {
    let levels: [Float]
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 3
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: barWidth, height: max(4, CGFloat(level) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: levels)
        }
        .accessibilityElement()
        .accessibilityLabel(isActive ? "Microphone level" : "Not listening")
    }
}

// MARK: - Helpers

extension View {
    /// Prominent full-width action using Liquid Glass.
    func primaryAction() -> some View {
        self
            .font(.headline)
            .buttonSizing(.flexible)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
    }

    func secondaryAction() -> some View {
        self
            .font(.headline)
            .buttonSizing(.flexible)
            .buttonStyle(.glass)
            .controlSize(.large)
    }
}

extension Date {
    var relativeDescription: String {
        formatted(.relative(presentation: .named))
    }
}
