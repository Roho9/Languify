import Foundation

/// Self-assessed recall for one review.
public enum ReviewGrade: Int, Codable, CaseIterable, Sendable, Identifiable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

/// Memory state of one card. `stability` is the number of days after which
/// recall probability falls to 90%; `difficulty` is in [1, 10].
public struct MemoryState: Codable, Equatable, Sendable {
    public var stability: Double
    public var difficulty: Double

    public init(stability: Double, difficulty: Double) {
        self.stability = stability
        self.difficulty = difficulty
    }
}

public struct ScheduledReview: Equatable, Sendable {
    public var state: MemoryState
    public var intervalDays: Int
    public var due: Date
}

/// FSRS v4.5 scheduler (Free Spaced Repetition Scheduler, open-spaced-repetition
/// project), with its published default parameters.
///
/// FSRS was chosen over SM-2 because it models retrievability explicitly,
/// adapts to each card's difficulty, and is benchmarked on millions of real
/// reviews. Same-day "short-term" reviews are not modelled, matching v4.5.
public struct FSRSScheduler: Sendable {
    public static let defaultWeights: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
        1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755,
    ]

    static let decay = -0.5
    static let factor = 19.0 / 81.0

    public let weights: [Double]
    /// Recall probability at which a card becomes due.
    public let desiredRetention: Double
    public let maximumIntervalDays: Int

    public init(weights: [Double] = FSRSScheduler.defaultWeights, desiredRetention: Double = 0.9, maximumIntervalDays: Int = 365) {
        precondition(weights.count == 17, "FSRS v4.5 expects 17 weights")
        precondition((0.7...0.99).contains(desiredRetention))
        self.weights = weights
        self.desiredRetention = desiredRetention
        self.maximumIntervalDays = maximumIntervalDays
    }

    /// Probability of recall `elapsedDays` after the last review.
    public func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + Self.factor * max(0, elapsedDays) / stability, Self.decay)
    }

    public func initialState(for grade: ReviewGrade) -> MemoryState {
        MemoryState(
            stability: max(0.1, weights[grade.rawValue - 1]),
            difficulty: initialDifficulty(grade)
        )
    }

    /// Next memory state after reviewing a card with `grade`.
    /// Pass `nil` for `previous` on a card's first review.
    public func nextState(previous: MemoryState?, elapsedDays: Double, grade: ReviewGrade) -> MemoryState {
        guard let previous else { return initialState(for: grade) }
        let r = retrievability(elapsedDays: elapsedDays, stability: previous.stability)
        let difficulty = nextDifficulty(previous.difficulty, grade: grade)
        let stability: Double
        if grade == .again {
            stability = forgetStability(difficulty: previous.difficulty, stability: previous.stability, retrievability: r)
        } else {
            stability = recallStability(difficulty: previous.difficulty, stability: previous.stability, retrievability: r, grade: grade)
        }
        return MemoryState(stability: max(0.1, stability), difficulty: difficulty)
    }

    /// Days until recall is expected to fall to `desiredRetention`.
    public func intervalDays(for stability: Double) -> Int {
        let raw = stability / Self.factor * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(maximumIntervalDays, max(1, Int(raw.rounded())))
    }

    public func schedule(previous: MemoryState?, lastReview: Date?, grade: ReviewGrade, now: Date) -> ScheduledReview {
        let elapsed = lastReview.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 0
        let state = nextState(previous: previous, elapsedDays: elapsed, grade: grade)
        // A lapse is shown again today rather than after a full day.
        let interval = grade == .again ? 0 : intervalDays(for: state.stability)
        let due = grade == .again ? now.addingTimeInterval(10 * 60) : now.addingTimeInterval(Double(interval) * 86_400)
        return ScheduledReview(state: state, intervalDays: interval, due: due)
    }

    // MARK: Formulas

    func initialDifficulty(_ grade: ReviewGrade) -> Double {
        clampDifficulty(weights[4] - Double(grade.rawValue - 3) * weights[5])
    }

    func nextDifficulty(_ d: Double, grade: ReviewGrade) -> Double {
        let next = d - weights[6] * Double(grade.rawValue - 3)
        let reverted = weights[7] * initialDifficulty(.good) + (1 - weights[7]) * next
        return clampDifficulty(reverted)
    }

    func recallStability(difficulty d: Double, stability s: Double, retrievability r: Double, grade: ReviewGrade) -> Double {
        let hardPenalty = grade == .hard ? weights[15] : 1
        let easyBonus = grade == .easy ? weights[16] : 1
        return s * (exp(weights[8]) * (11 - d) * pow(s, -weights[9]) * (exp((1 - r) * weights[10]) - 1) * hardPenalty * easyBonus + 1)
    }

    func forgetStability(difficulty d: Double, stability s: Double, retrievability r: Double) -> Double {
        let value = weights[11] * pow(d, -weights[12]) * (pow(s + 1, weights[13]) - 1) * exp((1 - r) * weights[14])
        // Forgetting never increases stability.
        return min(value, s)
    }

    func clampDifficulty(_ d: Double) -> Double { min(10, max(1, d)) }
}

/// Learning status shown in the journal, derived from memory state so it can
/// never disagree with the scheduler.
public enum LearningStatus: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case reviewing
    case mastered

    /// Cards whose 90%-recall horizon exceeds this many days are considered
    /// mastered and drop out of routine drilling.
    public static let masteryStabilityDays = 60.0

    public static func derive(state: MemoryState?, reviewCount: Int, manuallyMastered: Bool) -> LearningStatus {
        if manuallyMastered { return .mastered }
        guard let state, reviewCount > 0 else { return .new }
        if state.stability >= masteryStabilityDays { return .mastered }
        if state.stability >= 7 { return .reviewing }
        return .learning
    }

    public var label: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .reviewing: "Reviewing"
        case .mastered: "Mastered"
        }
    }
}
