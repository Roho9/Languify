import Foundation

public enum QuizQuestionType: String, Codable, Sendable {
    /// Shown the heritage word, pick its English meaning.
    case meaningRecognition
    /// Shown the English meaning, pick the heritage word.
    case vocabularyRecall
    /// Shown the original sentence with the word blanked out, pick the word.
    case contextualSelection
    /// Listen to the word (synthesised), pick the meaning.
    case listening
}

public struct QuizQuestion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let type: QuizQuestionType
    public let prompt: String
    /// Text to synthesise for listening questions.
    public let audioText: String?
    public let options: [String]
    public let correctIndex: Int
    public let cardID: UUID

    public var correctAnswer: String { options[correctIndex] }
}

/// Generates multiple-choice quizzes on-device from the learner's own saved
/// vocabulary, so quizzes work offline and reflect words they actually heard.
public struct QuizGenerator: Sendable {
    public init() {}

    public func makeQuiz<R: RandomNumberGenerator>(
        from cards: [StudyCard],
        count: Int,
        includeListening: Bool,
        using rng: inout R
    ) -> [QuizQuestion] {
        let usable = cards.filter { !$0.transliteration.isEmpty && !$0.englishMeaning.isEmpty }
        // Four options need at least four distinct meanings.
        guard Set(usable.map(\.englishMeaning)).count >= 4 else { return [] }

        var questions: [QuizQuestion] = []
        for card in usable.shuffled(using: &rng).prefix(count) {
            var types: [QuizQuestionType] = [.meaningRecognition, .vocabularyRecall]
            if let sentence = card.contextSentence, Self.blank(card.transliteration, in: sentence) != nil {
                types.append(.contextualSelection)
            }
            if includeListening { types.append(.listening) }
            let type = types.randomElement(using: &rng) ?? .meaningRecognition
            if let q = makeQuestion(type: type, card: card, pool: usable, rng: &rng) {
                questions.append(q)
            }
        }
        return questions
    }

    func makeQuestion<R: RandomNumberGenerator>(type: QuizQuestionType, card: StudyCard, pool: [StudyCard], rng: inout R) -> QuizQuestion? {
        let others = pool.filter { $0.id != card.id }
        func word(_ c: StudyCard) -> String { c.transliteration }
        let prompt: String
        let correct: String
        let distractorSource: [String]
        var audio: String?

        switch type {
        case .meaningRecognition:
            prompt = "What does \u{201C}\(card.transliteration)\u{201D} mean?"
            correct = card.englishMeaning
            distractorSource = others.map(\.englishMeaning)
        case .vocabularyRecall:
            prompt = "Which word means \u{201C}\(card.englishMeaning)\u{201D}?"
            correct = word(card)
            distractorSource = others.map(word)
        case .contextualSelection:
            guard let sentence = card.contextSentence, let blanked = Self.blank(card.transliteration, in: sentence) else { return nil }
            prompt = "Fill in the blank: \(blanked)"
            correct = word(card)
            distractorSource = others.map(word)
        case .listening:
            prompt = "Listen, then choose the meaning."
            audio = card.nativeScript.isEmpty ? card.transliteration : card.nativeScript
            correct = card.englishMeaning
            distractorSource = others.map(\.englishMeaning)
        }

        let distractors = Array(Set(distractorSource.filter { $0.caseInsensitiveCompare(correct) != .orderedSame }))
            .sorted()
            .shuffled(using: &rng)
            .prefix(3)
        guard distractors.count == 3 else { return nil }
        var options = Array(distractors) + [correct]
        options.shuffle(using: &rng)
        guard let index = options.firstIndex(of: correct) else { return nil }
        return QuizQuestion(id: UUID(), type: type, prompt: prompt, audioText: audio, options: options, correctIndex: index, cardID: card.id)
    }

    /// Replaces the first case-insensitive occurrence of `word` with a blank.
    static func blank(_ word: String, in sentence: String) -> String? {
        guard !word.isEmpty, let range = sentence.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        return sentence.replacingCharacters(in: range, with: "_____")
    }
}

/// Deterministic generator for tests and reproducible quizzes.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    public mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
