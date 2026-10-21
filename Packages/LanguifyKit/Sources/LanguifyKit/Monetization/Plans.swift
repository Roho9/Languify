import Foundation

public enum PlanTier: String, Codable, Sendable, CaseIterable {
    case free
    case premium
}

/// Features that can be gated by plan. Gating is configuration, not code.
public enum Feature: String, Codable, Sendable, CaseIterable {
    case liveRewind = "live_rewind"
    case detailedExplanations = "detailed_explanations"
    case vocabularyJournal = "vocabulary_journal"
    case flashcards = "flashcards"
    case quizzes = "quizzes"
    case advancedQuizzes = "advanced_quizzes"
    case conversationPractice = "conversation_practice"
    case pronunciationCoaching = "pronunciation_coaching"
    case personalizedLessons = "personalized_lessons"
    case learningAnalytics = "learning_analytics"
    case proactiveSuggestions = "proactive_suggestions"
}

/// Metered actions that count against daily quotas.
///
/// Raw values stay camelCase because they are dictionary keys: the API
/// client's snake_case key strategy converts them symmetrically on the wire.
public enum MeteredAction: String, Codable, Sendable, CaseIterable {
    case rewindQuestion
    case tutorTurn
    case lessonGeneration
    case pronunciationFeedback
}

public struct PlanDefinition: Codable, Equatable, Sendable {
    public var tier: PlanTier
    public var features: Set<Feature>
    /// Daily limits per action. A missing key means the action is not allowed.
    /// There is no "unlimited": premium limits are generous but finite to
    /// protect against runaway cloud cost and abuse.
    public var dailyLimits: [MeteredAction: Int]

    public init(tier: PlanTier, features: Set<Feature>, dailyLimits: [MeteredAction: Int]) {
        self.tier = tier
        self.features = features
        self.dailyLimits = dailyLimits
    }
}

/// Remote-configurable plan catalogue. The backend serves the live version at
/// `GET /v1/config`; `fallback` is used offline and on first launch.
public struct PlanCatalog: Codable, Equatable, Sendable {
    public var version: Int
    public var plans: [PlanTier: PlanDefinition]
    /// App Store product identifiers for the premium subscription.
    public var premiumProductIds: [String]

    public init(version: Int, plans: [PlanTier: PlanDefinition], premiumProductIds: [String]) {
        self.version = version
        self.plans = plans
        self.premiumProductIds = premiumProductIds
    }

    public func plan(_ tier: PlanTier) -> PlanDefinition {
        plans[tier] ?? PlanDefinition(tier: tier, features: [], dailyLimits: [:])
    }

    public static let fallback = PlanCatalog(
        version: 1,
        plans: [
            .free: PlanDefinition(
                tier: .free,
                features: [.liveRewind, .vocabularyJournal, .flashcards, .quizzes, .pronunciationCoaching],
                dailyLimits: [.rewindQuestion: 10, .pronunciationFeedback: 10, .tutorTurn: 0, .lessonGeneration: 0]
            ),
            .premium: PlanDefinition(
                tier: .premium,
                features: Set(Feature.allCases),
                dailyLimits: [.rewindQuestion: 200, .tutorTurn: 150, .lessonGeneration: 20, .pronunciationFeedback: 200]
            ),
        ],
        premiumProductIds: ["app.languify.premium.monthly", "app.languify.premium.annual"]
    )
}

/// Counts metered usage per calendar day in the user's time zone.
public struct UsageLedger: Codable, Equatable, Sendable {
    public var day: String
    public var counts: [MeteredAction: Int]

    public init(day: String = "", counts: [MeteredAction: Int] = [:]) {
        self.day = day
        self.counts = counts
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Resets counts when the day changes.
    public mutating func roll(to date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(for: date, calendar: calendar)
        if key != day {
            day = key
            counts = [:]
        }
    }

    public func used(_ action: MeteredAction) -> Int { counts[action] ?? 0 }

    public mutating func record(_ action: MeteredAction, at date: Date, calendar: Calendar = .current) {
        roll(to: date, calendar: calendar)
        counts[action, default: 0] += 1
    }
}

public enum AccessDecision: Equatable, Sendable {
    case allowed(remaining: Int)
    case featureLocked(Feature)
    case quotaExhausted(limit: Int)
}

/// Combines plan, catalogue and ledger to decide whether an action may run.
/// The backend enforces the same rules server-side; this client copy exists
/// so the UI can explain limits before a request is made.
public struct EntitlementResolver: Sendable {
    public var catalog: PlanCatalog
    public var tier: PlanTier

    public init(catalog: PlanCatalog, tier: PlanTier) {
        self.catalog = catalog
        self.tier = tier
    }

    public var plan: PlanDefinition { catalog.plan(tier) }

    public func has(_ feature: Feature) -> Bool { plan.features.contains(feature) }

    public func check(_ action: MeteredAction, feature: Feature, ledger: UsageLedger, now: Date, calendar: Calendar = .current) -> AccessDecision {
        guard has(feature) else { return .featureLocked(feature) }
        var ledger = ledger
        ledger.roll(to: now, calendar: calendar)
        let limit = plan.dailyLimits[action] ?? 0
        guard limit > 0 else { return .featureLocked(feature) }
        let remaining = limit - ledger.used(action)
        return remaining > 0 ? .allowed(remaining: remaining) : .quotaExhausted(limit: limit)
    }
}

extension PlanTier: CodingKeyRepresentable {}
extension MeteredAction: CodingKeyRepresentable {}
