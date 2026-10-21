import Foundation

/// Skill dimensions tracked for each learner.
public enum SkillDimension: String, Codable, CaseIterable, Sendable, Identifiable {
    case listening
    case speaking
    case vocabulary
    case pronunciation
    case sentenceConstruction
    case grammar

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .listening: "Listening"
        case .speaking: "Speaking"
        case .vocabulary: "Vocabulary"
        case .pronunciation: "Pronunciation"
        case .sentenceConstruction: "Sentences"
        case .grammar: "Grammar"
        }
    }
}

/// One skill score on a 0 to 100 scale, keeping what was *measured* by an
/// assessment separate from what is *estimated* from everyday activity.
public struct SkillScore: Codable, Equatable, Sendable {
    /// Rolling estimate from practice and rewind usage. Never shown as a test result.
    public var estimated: Double
    /// Most recent result of an explicit assessment, if one was taken.
    public var verified: Double?
    public var verifiedAt: Date?
    /// Number of evidence events behind `estimated`.
    public var evidenceCount: Int

    public init(estimated: Double, verified: Double? = nil, verifiedAt: Date? = nil, evidenceCount: Int = 0) {
        self.estimated = estimated
        self.verified = verified
        self.verifiedAt = verifiedAt
        self.evidenceCount = evidenceCount
    }
}

/// Evidence that nudges the estimated profile.
public enum LearningEvidence: Sendable, Equatable {
    /// The user asked what something meant. Mildly suggests a listening gap.
    case askedForMeaning
    case flashcardReviewed(ReviewGrade)
    case quizAnswered(dimension: SkillDimension, correct: Bool)
    /// Similarity in [0, 1] between the target and what the recogniser heard.
    case pronunciationAttempt(similarity: Double)
    /// AI tutor rating of a spoken turn, each in [0, 1].
    case tutorTurn(fluency: Double, grammar: Double, completeSentence: Bool)
}

/// Multidimensional learner profile, updated incrementally.
public struct LearnerProfile: Codable, Equatable, Sendable {
    public var scores: [SkillDimension: SkillScore]

    public init(scores: [SkillDimension: SkillScore]) {
        self.scores = scores
    }

    /// Seeds estimates from onboarding self-ratings (1 to 5). Seeds count as
    /// zero evidence so the first real events move them quickly.
    public static func seeded(from rating: SelfRating) -> LearnerProfile {
        func pct(_ v: Int) -> Double { Double(v - 1) / 4 * 100 }
        let speaking = pct(rating.speaking)
        return LearnerProfile(scores: [
            .listening: SkillScore(estimated: pct(rating.comprehension)),
            .speaking: SkillScore(estimated: speaking),
            .vocabulary: SkillScore(estimated: (pct(rating.comprehension) + speaking) / 2),
            .pronunciation: SkillScore(estimated: speaking),
            .sentenceConstruction: SkillScore(estimated: speaking),
            .grammar: SkillScore(estimated: speaking),
        ])
    }

    public func score(_ dimension: SkillDimension) -> SkillScore {
        scores[dimension] ?? SkillScore(estimated: 50)
    }

    /// Updates the estimate with an exponential moving average whose step size
    /// shrinks as evidence accumulates (floor 0.05), so one bad day does not
    /// erase months of progress.
    public mutating func record(_ evidence: LearningEvidence) {
        for (dimension, observation) in Self.observations(for: evidence) {
            var score = score(dimension)
            let alpha = max(0.05, 1.0 / Double(score.evidenceCount + 4))
            score.estimated = min(100, max(0, score.estimated + alpha * (observation - score.estimated)))
            score.evidenceCount += 1
            scores[dimension] = score
        }
    }

    public mutating func recordAssessment(_ dimension: SkillDimension, result: Double, at date: Date) {
        var score = score(dimension)
        score.verified = min(100, max(0, result))
        score.verifiedAt = date
        scores[dimension] = score
    }

    /// Dimensions sorted weakest first, by estimate.
    public var focusAreas: [SkillDimension] {
        SkillDimension.allCases.sorted { score($0).estimated < score($1).estimated }
    }

    static func observations(for evidence: LearningEvidence) -> [(SkillDimension, Double)] {
        switch evidence {
        case .askedForMeaning:
            return [(.listening, 55)]
        case .flashcardReviewed(let grade):
            let value: Double = switch grade {
            case .again: 20
            case .hard: 55
            case .good: 80
            case .easy: 95
            }
            return [(.vocabulary, value)]
        case .quizAnswered(let dimension, let correct):
            return [(dimension, correct ? 90 : 25)]
        case .pronunciationAttempt(let similarity):
            return [(.pronunciation, min(1, max(0, similarity)) * 100)]
        case .tutorTurn(let fluency, let grammar, let complete):
            return [
                (.speaking, min(1, max(0, fluency)) * 100),
                (.grammar, min(1, max(0, grammar)) * 100),
                (.sentenceConstruction, complete ? 85 : 35),
            ]
        }
    }
}

extension SkillDimension: CodingKeyRepresentable {}
