import Foundation
import LanguifyKit
import SwiftData

/// How a vocabulary entry entered the journal.
enum VocabularySource: String, Codable, CaseIterable {
    case liveRewind
    case suggestion
    case lesson
    case manual

    var label: String {
        switch self {
        case .liveRewind: "Live Rewind"
        case .suggestion: "Session suggestion"
        case .lesson: "Lesson"
        case .manual: "Added by you"
        }
    }
}

/// A word or phrase in the Smart Vocabulary Journal.
///
/// The schema is CloudKit-compatible (every property has a default, no unique
/// constraints, optional relationships) so iCloud sync can be switched on
/// without a migration. Raw audio is never stored; context is limited to the
/// single sentence the word appeared in.
@Model
final class VocabularyEntry {
    var id: UUID = UUID()
    /// De-duplication key from `VocabularyKey.make`.
    var key: String = ""
    var languageCode: String = HeritageLanguage.malayalam.rawValue
    var nativeScript: String = ""
    var transliteration: String = ""
    var englishMeaning: String = ""
    var contextualMeaning: String = ""
    var pronunciationHint: String = ""
    var partOfSpeech: String?
    var registerRaw: String = Register.unknown.rawValue
    var usageNote: String?
    var culturalNote: String?
    var regionalNote: String?
    /// The sentence the word was heard in (romanised), its native script and a natural translation.
    var contextSentence: String?
    var contextSentenceNative: String?
    var contextTranslation: String?
    var exampleNative: String?
    var exampleTransliteration: String?
    var exampleEnglish: String?
    var relatedWords: [String] = []
    var tags: [String] = []
    var sourceRaw: String = VocabularySource.liveRewind.rawValue
    var encounteredAt: Date = Date()
    var lastEncounteredAt: Date = Date()
    var encounterCount: Int = 1
    var isFavorite: Bool = false
    var manuallyMastered: Bool = false
    /// True once the learner corrected any field.
    var userEdited: Bool = false
    /// The AI's original meaning, kept when the learner corrects it.
    var originalEnglishMeaning: String?

    // Spaced repetition (FSRS)
    var stability: Double?
    var difficulty: Double?
    var lastReviewedAt: Date?
    var dueAt: Date?
    var reviewCount: Int = 0
    var lapseCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \ReviewRecord.entry)
    var reviews: [ReviewRecord]? = []

    init(language: HeritageLanguage, explanation item: VocabularyExplanation, source: VocabularySource, now: Date = Date()) {
        self.id = UUID()
        self.languageCode = language.rawValue
        self.key = VocabularyKey.make(language: language, nativeScript: item.nativeScript, transliteration: item.transliteration)
        self.sourceRaw = source.rawValue
        self.encounteredAt = now
        self.lastEncounteredAt = now
        apply(item)
    }

    init(language: HeritageLanguage, nativeScript: String, transliteration: String, englishMeaning: String, source: VocabularySource = .manual) {
        self.id = UUID()
        self.languageCode = language.rawValue
        self.nativeScript = nativeScript
        self.transliteration = transliteration
        self.englishMeaning = englishMeaning
        self.key = VocabularyKey.make(language: language, nativeScript: nativeScript, transliteration: transliteration)
        self.sourceRaw = source.rawValue
    }

    /// Fills AI-provided fields without overwriting the learner's corrections.
    func apply(_ item: VocabularyExplanation) {
        if !userEdited {
            nativeScript = item.nativeScript.isEmpty ? nativeScript : item.nativeScript
            transliteration = item.transliteration.isEmpty ? transliteration : item.transliteration
            englishMeaning = item.englishMeaning
        }
        contextualMeaning = item.contextualMeaning
        pronunciationHint = item.pronunciationHint
        partOfSpeech = item.partOfSpeech
        registerRaw = item.register.rawValue
        usageNote = item.usageNote
        culturalNote = item.culturalNote
        regionalNote = item.regionalNote
        exampleNative = item.example?.nativeScript
        exampleTransliteration = item.example?.transliteration
        exampleEnglish = item.example?.english
        relatedWords = item.related
    }

    var language: HeritageLanguage { HeritageLanguage(rawValue: languageCode) ?? .malayalam }
    var source: VocabularySource { VocabularySource(rawValue: sourceRaw) ?? .manual }
    var register: Register { Register(rawValue: registerRaw) ?? .unknown }

    var memory: MemoryState? {
        guard let stability, let difficulty else { return nil }
        return MemoryState(stability: stability, difficulty: difficulty)
    }

    var status: LearningStatus {
        LearningStatus.derive(state: memory, reviewCount: reviewCount, manuallyMastered: manuallyMastered)
    }

    var studyCard: StudyCard {
        StudyCard(
            id: id,
            nativeScript: nativeScript,
            transliteration: transliteration,
            englishMeaning: englishMeaning,
            contextSentence: contextSentence,
            contextTranslation: contextTranslation,
            memory: memory,
            lastReviewedAt: lastReviewedAt,
            dueAt: dueAt,
            reviewCount: reviewCount,
            isMastered: manuallyMastered
        )
    }

    /// Text best suited to speech synthesis: native script when present.
    var speakableText: String { nativeScript.isEmpty ? transliteration : nativeScript }
}

@Model
final class ReviewRecord {
    var id: UUID = UUID()
    var reviewedAt: Date = Date()
    var grade: Int = ReviewGrade.good.rawValue
    var entry: VocabularyEntry?

    init(grade: ReviewGrade, at date: Date) {
        self.grade = grade.rawValue
        self.reviewedAt = date
    }
}

enum LanguifySchema {
    static let models: [any PersistentModel.Type] = [VocabularyEntry.self, ReviewRecord.self]

    /// Builds the store. iCloud sync is opt-in and needs the iCloud
    /// entitlement plus a signed-in iCloud account; if CloudKit cannot be used
    /// the app falls back to local-only storage rather than failing.
    static func makeContainer(syncWithICloud: Bool, inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        if inMemory {
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        if syncWithICloud, FileManager.default.ubiquityIdentityToken != nil {
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(cloudKitDatabase: .private(AppConfiguration.iCloudContainer)))
            } catch {
                Log.data.error("CloudKit store unavailable, using local store: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(cloudKitDatabase: .none))
        } catch {
            Log.data.fault("Local store failed: \(error.localizedDescription, privacy: .public)")
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
    }
}
