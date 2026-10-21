import Foundation

/// A value-type view of a saved vocabulary entry, used by the learning
/// engine so it does not depend on the persistence layer.
public struct StudyCard: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var nativeScript: String
    public var transliteration: String
    public var englishMeaning: String
    public var contextSentence: String?
    public var contextTranslation: String?
    public var memory: MemoryState?
    public var lastReviewedAt: Date?
    public var dueAt: Date?
    public var reviewCount: Int
    public var isMastered: Bool

    public init(
        id: UUID = UUID(),
        nativeScript: String,
        transliteration: String,
        englishMeaning: String,
        contextSentence: String? = nil,
        contextTranslation: String? = nil,
        memory: MemoryState? = nil,
        lastReviewedAt: Date? = nil,
        dueAt: Date? = nil,
        reviewCount: Int = 0,
        isMastered: Bool = false
    ) {
        self.id = id
        self.nativeScript = nativeScript
        self.transliteration = transliteration
        self.englishMeaning = englishMeaning
        self.contextSentence = contextSentence
        self.contextTranslation = contextTranslation
        self.memory = memory
        self.lastReviewedAt = lastReviewedAt
        self.dueAt = dueAt
        self.reviewCount = reviewCount
        self.isMastered = isMastered
    }

    public var status: LearningStatus {
        LearningStatus.derive(state: memory, reviewCount: reviewCount, manuallyMastered: isMastered)
    }
}

/// Builds review sessions: overdue cards first (most overdue first), then new
/// cards, skipping mastered ones.
public enum ReviewQueue {
    public static func build(from cards: [StudyCard], now: Date, newLimit: Int = 10, totalLimit: Int = 30) -> [StudyCard] {
        let active = cards.filter { !$0.isMastered && $0.status != .mastered }
        let due = active
            .filter { $0.reviewCount > 0 && ($0.dueAt ?? .distantPast) <= now }
            .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
        let fresh = active.filter { $0.reviewCount == 0 }.prefix(newLimit)
        return Array((due + fresh).prefix(totalLimit))
    }

    public static func dueCount(in cards: [StudyCard], now: Date) -> Int {
        build(from: cards, now: now, newLimit: .max, totalLimit: .max).count
    }
}
