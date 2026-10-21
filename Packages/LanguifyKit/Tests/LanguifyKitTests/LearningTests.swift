import Foundation
import Testing
@testable import LanguifyKit

@Suite("FSRS")
struct FSRSTests {
    let fsrs = FSRSScheduler()

    @Test func retrievabilityIsNinetyPercentAtStability() {
        let r = fsrs.retrievability(elapsedDays: 10, stability: 10)
        #expect(abs(r - 0.9) < 1e-9)
        #expect(fsrs.retrievability(elapsedDays: 0, stability: 10) == 1)
    }

    @Test func intervalEqualsStabilityAtDefaultRetention() {
        #expect(fsrs.intervalDays(for: 10) == 10)
        #expect(fsrs.intervalDays(for: 0.2) == 1)
        #expect(fsrs.intervalDays(for: 10_000) == 365)
    }

    @Test func higherRetentionMeansShorterIntervals() {
        let strict = FSRSScheduler(desiredRetention: 0.95)
        #expect(strict.intervalDays(for: 20) < fsrs.intervalDays(for: 20))
    }

    @Test func initialStabilityMatchesWeights() {
        for grade in ReviewGrade.allCases {
            #expect(fsrs.initialState(for: grade).stability == FSRSScheduler.defaultWeights[grade.rawValue - 1])
        }
    }

    @Test func gradesAreOrderedForEveryReview() {
        let state = MemoryState(stability: 5, difficulty: 5)
        let next = ReviewGrade.allCases.map { fsrs.nextState(previous: state, elapsedDays: 5, grade: $0).stability }
        #expect(next[0] < next[1])
        #expect(next[1] < next[2])
        #expect(next[2] < next[3])
    }

    @Test func lapseNeverIncreasesStability() {
        let state = MemoryState(stability: 30, difficulty: 3)
        let after = fsrs.nextState(previous: state, elapsedDays: 30, grade: .again)
        #expect(after.stability <= state.stability)
    }

    @Test func difficultyStaysInRange() {
        var state = fsrs.initialState(for: .again)
        for _ in 0..<50 { state = fsrs.nextState(previous: state, elapsedDays: 1, grade: .again) }
        #expect(state.difficulty <= 10 && state.difficulty >= 1)
        for _ in 0..<50 { state = fsrs.nextState(previous: state, elapsedDays: 1, grade: .easy) }
        #expect(state.difficulty <= 10 && state.difficulty >= 1)
    }

    @Test func consistentGoodReviewsLeadToMastery() {
        let start = Date(timeIntervalSince1970: 0)
        var now = start
        var state: MemoryState?
        var last: Date?
        var reviews = 0
        while LearningStatus.derive(state: state, reviewCount: reviews, manuallyMastered: false) != .mastered && reviews < 20 {
            let result = fsrs.schedule(previous: state, lastReview: last, grade: .good, now: now)
            state = result.state
            last = now
            now = result.due
            reviews += 1
        }
        #expect(reviews < 10, "Good reviews should master a card within a handful of reviews")
    }

    @Test func againIsDueWithinTheSession() {
        let now = Date()
        let r = fsrs.schedule(previous: MemoryState(stability: 10, difficulty: 5), lastReview: now.addingTimeInterval(-86_400 * 10), grade: .again, now: now)
        #expect(r.intervalDays == 0)
        #expect(r.due.timeIntervalSince(now) <= 15 * 60)
    }
}

@Suite("ReviewQueue")
struct ReviewQueueTests {
    @Test func overdueFirstThenNewSkippingMastered() {
        let now = Date()
        let overdue = StudyCard(nativeScript: "", transliteration: "a", englishMeaning: "A", memory: MemoryState(stability: 3, difficulty: 5), dueAt: now.addingTimeInterval(-86_400 * 3), reviewCount: 2)
        let slightlyDue = StudyCard(nativeScript: "", transliteration: "b", englishMeaning: "B", memory: MemoryState(stability: 3, difficulty: 5), dueAt: now.addingTimeInterval(-60), reviewCount: 1)
        let notDue = StudyCard(nativeScript: "", transliteration: "c", englishMeaning: "C", memory: MemoryState(stability: 3, difficulty: 5), dueAt: now.addingTimeInterval(86_400), reviewCount: 1)
        let fresh = StudyCard(nativeScript: "", transliteration: "d", englishMeaning: "D")
        let mastered = StudyCard(nativeScript: "", transliteration: "e", englishMeaning: "E", memory: MemoryState(stability: 100, difficulty: 2), dueAt: now.addingTimeInterval(-86_400), reviewCount: 8)
        let manual = StudyCard(nativeScript: "", transliteration: "f", englishMeaning: "F", isMastered: true)
        let queue = ReviewQueue.build(from: [fresh, notDue, slightlyDue, mastered, overdue, manual], now: now)
        #expect(queue.map(\.transliteration) == ["a", "b", "d"])
    }

    @Test func respectsLimits() {
        let cards = (0..<50).map { StudyCard(nativeScript: "", transliteration: "w\($0)", englishMeaning: "m\($0)") }
        #expect(ReviewQueue.build(from: cards, now: Date(), newLimit: 5).count == 5)
    }
}

@Suite("LearnerProfile")
struct LearnerProfileTests {
    @Test func seedsFromSelfRating() {
        let p = LearnerProfile.seeded(from: SelfRating(comprehension: 5, speaking: 1, reading: 1))
        #expect(p.score(.listening).estimated == 100)
        #expect(p.score(.speaking).estimated == 0)
        #expect(p.score(.listening).verified == nil)
        #expect(p.focusAreas.first != .listening)
    }

    @Test func evidenceMovesEstimateButNotVerified() {
        var p = LearnerProfile.seeded(from: SelfRating(comprehension: 3, speaking: 1, reading: 1))
        for _ in 0..<10 { p.record(.pronunciationAttempt(similarity: 0.9)) }
        #expect(p.score(.pronunciation).estimated > 60)
        #expect(p.score(.pronunciation).verified == nil)
        #expect(p.score(.pronunciation).evidenceCount == 10)
    }

    @Test func assessmentIsStoredSeparately() {
        var p = LearnerProfile.seeded(from: SelfRating())
        let estimate = p.score(.listening).estimated
        p.recordAssessment(.listening, result: 140, at: Date())
        #expect(p.score(.listening).verified == 100)
        #expect(p.score(.listening).estimated == estimate)
    }

    @Test func roundTripsThroughJSON() throws {
        var p = LearnerProfile.seeded(from: SelfRating())
        p.record(.tutorTurn(fluency: 0.5, grammar: 0.4, completeSentence: true))
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(LearnerProfile.self, from: data) == p)
        #expect(String(decoding: data, as: UTF8.self).contains("\"listening\""))
    }
}

@Suite("QuizGenerator")
struct QuizGeneratorTests {
    let cards: [StudyCard] = [
        StudyCard(nativeScript: "മടി", transliteration: "madi", englishMeaning: "laziness", contextSentence: "avanu bhayankara madi aanu"),
        StudyCard(nativeScript: "വിശപ്പ്", transliteration: "vishappu", englishMeaning: "hunger"),
        StudyCard(nativeScript: "സന്തോഷം", transliteration: "santhosham", englishMeaning: "happiness"),
        StudyCard(nativeScript: "ദേഷ്യം", transliteration: "deshyam", englishMeaning: "anger"),
        StudyCard(nativeScript: "ഉറക്കം", transliteration: "urakkam", englishMeaning: "sleep"),
    ]

    @Test func generatesValidQuestions() {
        var rng = SeededGenerator(seed: 42)
        let quiz = QuizGenerator().makeQuiz(from: cards, count: 5, includeListening: true, using: &rng)
        #expect(quiz.count == 5)
        for q in quiz {
            #expect(q.options.count == 4)
            #expect(Set(q.options).count == 4)
            let card = cards.first { $0.id == q.cardID }!
            switch q.type {
            case .meaningRecognition, .listening: #expect(q.correctAnswer == card.englishMeaning)
            case .vocabularyRecall, .contextualSelection: #expect(q.correctAnswer == card.transliteration)
            }
        }
    }

    @Test func isDeterministicWithSeed() {
        var a = SeededGenerator(seed: 7), b = SeededGenerator(seed: 7)
        let q1 = QuizGenerator().makeQuiz(from: cards, count: 3, includeListening: false, using: &a)
        let q2 = QuizGenerator().makeQuiz(from: cards, count: 3, includeListening: false, using: &b)
        #expect(q1.map(\.prompt) == q2.map(\.prompt))
        #expect(q1.map(\.options) == q2.map(\.options))
    }

    @Test func needsEnoughDistinctWords() {
        var rng = SeededGenerator(seed: 1)
        #expect(QuizGenerator().makeQuiz(from: Array(cards.prefix(3)), count: 3, includeListening: false, using: &rng).isEmpty)
    }

    @Test func blanksWordInContext() {
        #expect(QuizGenerator.blank("madi", in: "avanu Madi aanu") == "avanu _____ aanu")
        #expect(QuizGenerator.blank("xyz", in: "avanu madi aanu") == nil)
    }
}

@Suite("PronunciationScorer")
struct PronunciationScorerTests {
    let scorer = PronunciationScorer()

    @Test func toleratesRomanisationVariants() {
        let r = scorer.score(target: "enna vēṇum", heard: "enna vaenum")
        #expect(r.verdict == .recognized)
        #expect(r.words.allSatisfy { $0.matched })
    }

    @Test func doubledLettersAndCase() {
        #expect(scorer.score(target: "naalaikku", heard: "Nalaiku").verdict == .recognized)
    }

    @Test func detectsDifferentWord() {
        let r = scorer.score(target: "santhosham", heard: "deshyam")
        #expect(r.verdict == .different)
        #expect(r.similarity < 0.6)
    }

    @Test func emptyHeardIsNothingHeard() {
        let r = scorer.score(target: "madi", heard: "  ")
        #expect(r.verdict == .nothingHeard)
        #expect(r.similarity == 0)
    }

    @Test func levenshtein() {
        #expect(PronunciationScorer.levenshtein(Array("kitten"), Array("sitting")) == 3)
        #expect(PronunciationScorer.levenshtein([], Array("abc")) == 3)
    }

    @Test func vocabularyKeyPrefersNativeScript() {
        #expect(VocabularyKey.make(language: .malayalam, nativeScript: " മടി ", transliteration: "madi") == "ml:n:മടി")
        #expect(VocabularyKey.make(language: .tamil, nativeScript: "", transliteration: "Vaenum") == VocabularyKey.make(language: .tamil, nativeScript: "", transliteration: "venum"))
    }
}
