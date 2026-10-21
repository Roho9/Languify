import Foundation

/// One recognised stretch of speech within a rewind window.
public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var text: String
    /// Seconds from the start of the analysed window.
    public var start: Double
    public var end: Double
    /// Mean of the recogniser's per-token confidence, when it reported one.
    /// `SpeechTranscriber` exposes this through the `transcriptionConfidence`
    /// attribute; it is never synthesised.
    public var confidence: Double?
    /// Other hypotheses the recogniser produced for this segment.
    public var alternatives: [String]

    public init(text: String, start: Double, end: Double, confidence: Double? = nil, alternatives: [String] = []) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.alternatives = alternatives
    }
}

/// Transcription of a rewind window in the heritage language and, for
/// code-switched speech, in English.
public struct RewindTranscript: Codable, Equatable, Sendable {
    public var languageCode: String
    /// Segments from the heritage-language recogniser. Apple's Tamil and
    /// Malayalam models emit romanised (Latin) text, not native script.
    public var primary: [TranscriptSegment]
    /// Segments from the English recogniser over the same audio.
    public var english: [TranscriptSegment]
    public var windowSeconds: Double

    public init(languageCode: String, primary: [TranscriptSegment], english: [TranscriptSegment], windowSeconds: Double) {
        self.languageCode = languageCode
        self.primary = primary
        self.english = english
        self.windowSeconds = windowSeconds
    }

    public var isEmpty: Bool {
        primary.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && english.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var primaryText: String {
        primary.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last sentence-like segment, used for quick display.
    public var lastUtterance: String? {
        primary.last(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })?.text
            .trimmingCharacters(in: .whitespaces)
    }

    /// True when any primary segment reports low recogniser confidence.
    public func hasLowConfidence(threshold: Double = 0.6) -> Bool {
        primary.contains { ($0.confidence ?? 1) < threshold }
    }
}

/// What the user wants to know about the recent speech.
public enum RewindQuestionKind: String, Codable, CaseIterable, Sendable {
    case auto
    case word
    case sentence
    case expression
    case gist
    case respond
    case grammar
    case pronunciation

    public var defaultQuestion: String {
        switch self {
        case .auto, .gist: "Can you explain what was just said?"
        case .word: "What did that last word mean?"
        case .sentence: "What did that last sentence mean?"
        case .expression: "What does that expression mean?"
        case .respond: "How would I respond?"
        case .grammar: "Can you explain the grammar in that sentence?"
        case .pronunciation: "How do I pronounce that word?"
        }
    }

    public var label: String {
        switch self {
        case .auto: "Ask"
        case .word: "That word"
        case .sentence: "That sentence"
        case .expression: "That expression"
        case .gist: "What was said"
        case .respond: "How to reply"
        case .grammar: "Grammar"
        case .pronunciation: "Pronounce it"
        }
    }

    public var symbolName: String {
        switch self {
        case .auto: "questionmark.bubble"
        case .word: "character.bubble"
        case .sentence: "text.bubble"
        case .expression: "quote.bubble"
        case .gist: "text.alignleft"
        case .respond: "arrowshape.turn.up.left"
        case .grammar: "textformat.abc"
        case .pronunciation: "waveform"
        }
    }

    /// Lightweight keyword inference for free-form questions. The AI makes the
    /// final call; this only seeds the request so dedicated UI can respond fast.
    public static func infer(from question: String) -> RewindQuestionKind {
        let q = question.lowercased()
        func has(_ words: String...) -> Bool { words.contains { q.contains($0) } }
        if has("respond", "reply", "answer", "how do i say", "how would i say", "what should i say") { return .respond }
        if has("pronounc", "how do i say that word", "say it") { return .pronunciation }
        if has("grammar", "tense", "conjugat", "why is it") { return .grammar }
        if has("expression", "idiom", "saying", "phrase") { return .expression }
        if has("difference between") { return .word }
        if has("sentence") { return .sentence }
        if has("word", "sounded like", "sounds like", "mean by") { return .word }
        if has("what was said", "what did they say", "what was just said", "explain", "simpler") { return .gist }
        return .auto
    }
}
