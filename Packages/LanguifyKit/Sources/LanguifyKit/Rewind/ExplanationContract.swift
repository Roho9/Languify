import Foundation

/// Request body for `POST /v1/rewind/explain`. Only text leaves the device:
/// the transcript is produced on-device and raw audio is never uploaded.
public struct RewindExplainRequest: Codable, Equatable, Sendable {
    public var language: HeritageLanguage
    public var question: String
    public var kind: RewindQuestionKind
    /// The user's rough spelling of what they heard ("sounded like 'madi'").
    public var soundsLike: String?
    /// Free-form context the user supplied, e.g. "my mom was talking about dinner".
    public var userContext: String?
    public var transcript: RewindTranscript
    public var learner: LearnerSnapshot
    public var clarification: ClarificationAnswer?
    /// Explicit user choice to receive a longer explanation.
    public var detailLevel: DetailLevel

    public init(
        language: HeritageLanguage,
        question: String,
        kind: RewindQuestionKind,
        soundsLike: String? = nil,
        userContext: String? = nil,
        transcript: RewindTranscript,
        learner: LearnerSnapshot,
        clarification: ClarificationAnswer? = nil,
        detailLevel: DetailLevel = .concise
    ) {
        self.language = language
        self.question = question
        self.kind = kind
        self.soundsLike = soundsLike
        self.userContext = userContext
        self.transcript = transcript
        self.learner = learner
        self.clarification = clarification
        self.detailLevel = detailLevel
    }
}

public enum DetailLevel: String, Codable, Sendable {
    case concise
    case detailed
}

public struct ClarificationAnswer: Codable, Equatable, Sendable {
    public var question: String
    public var chosenOption: String

    public init(question: String, chosenOption: String) {
        self.question = question
        self.chosenOption = chosenOption
    }
}

/// The minimal learner context sent with AI requests.
public struct LearnerSnapshot: Codable, Equatable, Sendable {
    public var comprehension: Int
    public var speaking: Int
    public var reading: Int
    /// A handful of recently saved transliterations, so explanations can
    /// connect to words the user already knows.
    public var recentWords: [String]

    public init(comprehension: Int, speaking: Int, reading: Int, recentWords: [String] = []) {
        self.comprehension = comprehension
        self.speaking = speaking
        self.reading = reading
        self.recentWords = Array(recentWords.prefix(20))
    }
}

// MARK: - Response

public enum ExplanationStatus: String, Codable, Sendable {
    case answered
    case needsClarification = "needs_clarification"
    case noRelevantSpeech = "no_relevant_speech"
    case uncertain
}

public enum Register: String, Codable, Sendable {
    case formal, informal, neutral, unknown
}

public struct LocalizedPhrase: Codable, Equatable, Sendable, Hashable {
    public var nativeScript: String
    public var transliteration: String
    public var english: String

    public init(nativeScript: String, transliteration: String, english: String) {
        self.nativeScript = nativeScript
        self.transliteration = transliteration
        self.english = english
    }
}

public struct HeardUtterance: Codable, Equatable, Sendable {
    public var nativeScript: String
    public var transliteration: String
    /// Natural English rendering, not word for word.
    public var englishNatural: String
    public var literalGloss: String?

    public init(nativeScript: String, transliteration: String, englishNatural: String, literalGloss: String? = nil) {
        self.nativeScript = nativeScript
        self.transliteration = transliteration
        self.englishNatural = englishNatural
        self.literalGloss = literalGloss
    }
}

public struct VocabularyExplanation: Codable, Equatable, Sendable {
    public var nativeScript: String
    public var transliteration: String
    public var englishMeaning: String
    public var contextualMeaning: String
    public var pronunciationHint: String
    public var partOfSpeech: String?
    public var register: Register
    public var usageNote: String?
    public var culturalNote: String?
    public var regionalNote: String?
    public var example: LocalizedPhrase?
    public var related: [String]

    public init(
        nativeScript: String,
        transliteration: String,
        englishMeaning: String,
        contextualMeaning: String,
        pronunciationHint: String,
        partOfSpeech: String? = nil,
        register: Register = .unknown,
        usageNote: String? = nil,
        culturalNote: String? = nil,
        regionalNote: String? = nil,
        example: LocalizedPhrase? = nil,
        related: [String] = []
    ) {
        self.nativeScript = nativeScript
        self.transliteration = transliteration
        self.englishMeaning = englishMeaning
        self.contextualMeaning = contextualMeaning
        self.pronunciationHint = pronunciationHint
        self.partOfSpeech = partOfSpeech
        self.register = register
        self.usageNote = usageNote
        self.culturalNote = culturalNote
        self.regionalNote = regionalNote
        self.example = example
        self.related = related
    }
}

public struct ClarificationPrompt: Codable, Equatable, Sendable {
    public var question: String
    public var options: [String]

    public init(question: String, options: [String]) {
        self.question = question
        self.options = options
    }
}

public struct AlternativeReading: Codable, Equatable, Sendable {
    public var transliteration: String
    public var englishMeaning: String

    public init(transliteration: String, englishMeaning: String) {
        self.transliteration = transliteration
        self.englishMeaning = englishMeaning
    }
}

/// Structured explanation returned by the AI service.
public struct RewindExplanation: Codable, Equatable, Sendable {
    public var status: ExplanationStatus
    public var kind: RewindQuestionKind
    /// One or two short English sentences suitable for speaking in an ear.
    public var spokenSummary: String
    public var heard: HeardUtterance?
    public var items: [VocabularyExplanation]
    public var suggestedReplies: [LocalizedPhrase]
    public var grammarNote: String?
    public var clarification: ClarificationPrompt?
    public var alternatives: [AlternativeReading]
    public var uncertaintyNote: String?

    public init(
        status: ExplanationStatus,
        kind: RewindQuestionKind,
        spokenSummary: String,
        heard: HeardUtterance? = nil,
        items: [VocabularyExplanation] = [],
        suggestedReplies: [LocalizedPhrase] = [],
        grammarNote: String? = nil,
        clarification: ClarificationPrompt? = nil,
        alternatives: [AlternativeReading] = [],
        uncertaintyNote: String? = nil
    ) {
        self.status = status
        self.kind = kind
        self.spokenSummary = spokenSummary
        self.heard = heard
        self.items = items
        self.suggestedReplies = suggestedReplies
        self.grammarNote = grammarNote
        self.clarification = clarification
        self.alternatives = alternatives
        self.uncertaintyNote = uncertaintyNote
    }
}

// MARK: - Validation

public enum ExplanationValidationError: Error, Equatable, Sendable {
    case emptySummary
    case answeredWithoutContent
    case clarificationMissingOptions
}

/// Validates AI output before it is shown, spoken or saved.
///
/// Hard failures throw. Recoverable problems (for example a "native script"
/// field that contains no native characters) are repaired by blanking the
/// field, and a warning is recorded so the UI never presents bad data as fact.
public struct ExplanationValidator: Sendable {
    public static let maxItems = 5
    public static let maxSummaryCharacters = 420

    public let language: HeritageLanguage

    public init(language: HeritageLanguage) {
        self.language = language
    }

    public struct Result: Sendable, Equatable {
        public var explanation: RewindExplanation
        public var warnings: [String]
    }

    public func validate(_ raw: RewindExplanation) throws -> Result {
        var e = raw
        var warnings: [String] = []

        e.spokenSummary = e.spokenSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.spokenSummary.isEmpty else { throw ExplanationValidationError.emptySummary }
        if e.spokenSummary.count > Self.maxSummaryCharacters {
            e.spokenSummary = String(e.spokenSummary.prefix(Self.maxSummaryCharacters))
            warnings.append("Summary truncated")
        }

        if e.items.count > Self.maxItems {
            e.items = Array(e.items.prefix(Self.maxItems))
            warnings.append("Extra items dropped")
        }

        let config = language.configuration
        func repairScript(_ text: inout String, field: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !config.containsNativeScript(trimmed) {
                text = ""
                warnings.append("\(field) was not in \(config.scriptName)")
            } else {
                text = trimmed
            }
        }

        e.items = e.items.compactMap { item in
            var item = item
            item.transliteration = item.transliteration.trimmingCharacters(in: .whitespacesAndNewlines)
            item.englishMeaning = item.englishMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.transliteration.isEmpty || !item.nativeScript.isEmpty, !item.englishMeaning.isEmpty else {
                warnings.append("Dropped an incomplete vocabulary item")
                return nil
            }
            repairScript(&item.nativeScript, field: "Word script")
            if var example = item.example {
                repairScript(&example.nativeScript, field: "Example script")
                item.example = example.transliteration.isEmpty && example.english.isEmpty ? nil : example
            }
            return item
        }

        if var heard = e.heard {
            repairScript(&heard.nativeScript, field: "Sentence script")
            e.heard = heard.transliteration.isEmpty && heard.englishNatural.isEmpty ? nil : heard
        }

        e.suggestedReplies = e.suggestedReplies.compactMap { reply in
            var reply = reply
            repairScript(&reply.nativeScript, field: "Reply script")
            return reply.transliteration.isEmpty && reply.nativeScript.isEmpty ? nil : reply
        }

        switch e.status {
        case .needsClarification:
            let options = (e.clarification?.options ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let question = e.clarification?.question, !question.isEmpty, options.count >= 2 else {
                throw ExplanationValidationError.clarificationMissingOptions
            }
            e.clarification = ClarificationPrompt(question: question, options: Array(options.prefix(4)))
        case .answered:
            if e.items.isEmpty && e.heard == nil && e.suggestedReplies.isEmpty && (e.grammarNote ?? "").isEmpty {
                throw ExplanationValidationError.answeredWithoutContent
            }
            e.clarification = nil
        case .uncertain, .noRelevantSpeech:
            e.clarification = nil
        }

        return Result(explanation: e, warnings: warnings)
    }
}
