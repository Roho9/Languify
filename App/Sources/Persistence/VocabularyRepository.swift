import Foundation
import LanguifyKit
import SwiftData

/// All reads and writes of the vocabulary journal go through here.
final class VocabularyRepository {
    let context: ModelContext
    private let scheduler = FSRSScheduler()

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Queries

    func entries(language: HeritageLanguage? = nil) -> [VocabularyEntry] {
        var descriptor = FetchDescriptor<VocabularyEntry>(sortBy: [SortDescriptor(\.lastEncounteredAt, order: .reverse)])
        if let code = language?.rawValue {
            descriptor.predicate = #Predicate { $0.languageCode == code }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func entry(id: UUID) -> VocabularyEntry? {
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func entry(key: String) -> VocabularyEntry? {
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func recentTransliterations(language: HeritageLanguage, limit: Int = 20) -> [String] {
        entries(language: language).prefix(limit).map(\.transliteration).filter { !$0.isEmpty }
    }

    func dueCount(language: HeritageLanguage, now: Date = Date()) -> Int {
        ReviewQueue.dueCount(in: entries(language: language).map(\.studyCard), now: now)
    }

    // MARK: Saving from Live Rewind

    /// Saves each explained word, merging with an existing entry when the same
    /// word was saved before. Returns the affected entries.
    @discardableResult
    func save(
        _ items: [VocabularyExplanation],
        language: HeritageLanguage,
        heard: HeardUtterance?,
        fallbackContext: String?,
        source: VocabularySource,
        now: Date = Date()
    ) -> [VocabularyEntry] {
        var saved: [VocabularyEntry] = []
        for item in items {
            let key = VocabularyKey.make(language: language, nativeScript: item.nativeScript, transliteration: item.transliteration)
            let entry: VocabularyEntry
            if let existing = self.entry(key: key) {
                existing.apply(item)
                existing.encounterCount += 1
                existing.lastEncounteredAt = now
                entry = existing
            } else {
                entry = VocabularyEntry(language: language, explanation: item, source: source, now: now)
                context.insert(entry)
            }
            // Keep only the one sentence the word appeared in.
            if let heard {
                entry.contextSentence = heard.transliteration
                entry.contextSentenceNative = heard.nativeScript.isEmpty ? nil : heard.nativeScript
                entry.contextTranslation = heard.englishNatural
            } else if entry.contextSentence == nil, let fallbackContext {
                entry.contextSentence = fallbackContext
            }
            saved.append(entry)
        }
        persist()
        return saved
    }

    // MARK: Editing

    func correct(_ entry: VocabularyEntry, nativeScript: String, transliteration: String, englishMeaning: String) {
        if entry.originalEnglishMeaning == nil, englishMeaning != entry.englishMeaning {
            entry.originalEnglishMeaning = entry.englishMeaning
        }
        entry.nativeScript = nativeScript
        entry.transliteration = transliteration
        entry.englishMeaning = englishMeaning
        entry.key = VocabularyKey.make(language: entry.language, nativeScript: nativeScript, transliteration: transliteration)
        entry.userEdited = true
        persist()
    }

    func toggleFavorite(_ entry: VocabularyEntry) {
        entry.isFavorite.toggle()
        persist()
    }

    func setMastered(_ entry: VocabularyEntry, _ mastered: Bool) {
        entry.manuallyMastered = mastered
        persist()
    }

    func delete(_ entry: VocabularyEntry) {
        context.delete(entry)
        persist()
    }

    // MARK: Review

    /// Applies a review grade with FSRS and returns the next due date.
    @discardableResult
    func review(_ entry: VocabularyEntry, grade: ReviewGrade, now: Date = Date()) -> Date {
        let result = scheduler.schedule(previous: entry.memory, lastReview: entry.lastReviewedAt, grade: grade, now: now)
        entry.stability = result.state.stability
        entry.difficulty = result.state.difficulty
        entry.lastReviewedAt = now
        entry.dueAt = result.due
        entry.reviewCount += 1
        if grade == .again { entry.lapseCount += 1 }
        let record = ReviewRecord(grade: grade, at: now)
        context.insert(record)
        record.entry = entry
        persist()
        return result.due
    }

    // MARK: Data management

    func exportPayload() -> ([ExportedVocabulary], [ExportedReview]) {
        let all = entries()
        let vocab = all.map {
            ExportedVocabulary(
                id: $0.id, language: $0.languageCode, nativeScript: $0.nativeScript, transliteration: $0.transliteration,
                englishMeaning: $0.englishMeaning, contextualMeaning: $0.contextualMeaning, contextSentence: $0.contextSentence,
                encounteredAt: $0.encounteredAt, source: $0.sourceRaw, isFavorite: $0.isFavorite, status: $0.status.rawValue,
                tags: $0.tags, userEdited: $0.userEdited
            )
        }
        let reviews = all.flatMap { entry in
            (entry.reviews ?? []).map { ExportedReview(vocabularyID: entry.id, reviewedAt: $0.reviewedAt, grade: $0.grade) }
        }
        return (vocab, reviews)
    }

    func deleteLearningHistory() {
        try? context.delete(model: ReviewRecord.self)
        for entry in entries() {
            entry.stability = nil
            entry.difficulty = nil
            entry.lastReviewedAt = nil
            entry.dueAt = nil
            entry.reviewCount = 0
            entry.lapseCount = 0
            entry.manuallyMastered = false
        }
        persist()
    }

    func deleteAll() {
        try? context.delete(model: ReviewRecord.self)
        try? context.delete(model: VocabularyEntry.self)
        persist()
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            Log.data.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
