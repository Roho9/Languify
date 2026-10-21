import Foundation

/// Everything Languify stores about a learner, in a portable JSON format.
/// Raw audio is never part of an export because it is never stored.
public struct LearningDataExport: Codable, Sendable {
    public static let formatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var preferences: UserPreferences
    public var profile: LearnerProfile?
    public var vocabulary: [ExportedVocabulary]
    public var reviews: [ExportedReview]

    public init(exportedAt: Date, preferences: UserPreferences, profile: LearnerProfile?, vocabulary: [ExportedVocabulary], reviews: [ExportedReview]) {
        self.formatVersion = Self.formatVersion
        self.exportedAt = exportedAt
        self.preferences = preferences
        self.profile = profile
        self.vocabulary = vocabulary
        self.reviews = reviews
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public struct ExportedVocabulary: Codable, Sendable, Equatable {
    public var id: UUID
    public var language: String
    public var nativeScript: String
    public var transliteration: String
    public var englishMeaning: String
    public var contextualMeaning: String
    public var contextSentence: String?
    public var encounteredAt: Date
    public var source: String
    public var isFavorite: Bool
    public var status: String
    public var tags: [String]
    public var userEdited: Bool

    public init(id: UUID, language: String, nativeScript: String, transliteration: String, englishMeaning: String, contextualMeaning: String, contextSentence: String?, encounteredAt: Date, source: String, isFavorite: Bool, status: String, tags: [String], userEdited: Bool) {
        self.id = id
        self.language = language
        self.nativeScript = nativeScript
        self.transliteration = transliteration
        self.englishMeaning = englishMeaning
        self.contextualMeaning = contextualMeaning
        self.contextSentence = contextSentence
        self.encounteredAt = encounteredAt
        self.source = source
        self.isFavorite = isFavorite
        self.status = status
        self.tags = tags
        self.userEdited = userEdited
    }
}

public struct ExportedReview: Codable, Sendable, Equatable {
    public var vocabularyID: UUID
    public var reviewedAt: Date
    public var grade: Int

    public init(vocabularyID: UUID, reviewedAt: Date, grade: Int) {
        self.vocabularyID = vocabularyID
        self.reviewedAt = reviewedAt
        self.grade = grade
    }
}
