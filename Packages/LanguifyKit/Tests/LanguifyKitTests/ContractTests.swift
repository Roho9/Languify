import Foundation
import Testing
@testable import LanguifyKit

@Suite("ExplanationValidator")
struct ExplanationValidatorTests {
    let validator = ExplanationValidator(language: .malayalam)

    func item(native: String = "മടി", translit: String = "madi", meaning: String = "laziness") -> VocabularyExplanation {
        VocabularyExplanation(nativeScript: native, transliteration: translit, englishMeaning: meaning, contextualMeaning: "not wanting to do it", pronunciationHint: "MA-di")
    }

    @Test func acceptsWellFormedAnswer() throws {
        let e = RewindExplanation(status: .answered, kind: .word, spokenSummary: "Madi means laziness.", items: [item()])
        let result = try validator.validate(e)
        #expect(result.warnings.isEmpty)
        #expect(result.explanation.items.first?.nativeScript == "മടി")
    }

    @Test func blanksScriptInWrongLanguage() throws {
        // Tamil script where Malayalam was expected.
        let e = RewindExplanation(status: .answered, kind: .word, spokenSummary: "x", items: [item(native: "சோம்பல்")])
        let result = try validator.validate(e)
        #expect(result.explanation.items.first?.nativeScript == "")
        #expect(!result.warnings.isEmpty)
    }

    @Test func rejectsEmptySummary() {
        let e = RewindExplanation(status: .answered, kind: .word, spokenSummary: "  ", items: [item()])
        #expect(throws: ExplanationValidationError.emptySummary) { try validator.validate(e) }
    }

    @Test func rejectsAnswerWithoutContent() {
        let e = RewindExplanation(status: .answered, kind: .word, spokenSummary: "It means something.")
        #expect(throws: ExplanationValidationError.answeredWithoutContent) { try validator.validate(e) }
    }

    @Test func clarificationNeedsTwoOptions() throws {
        let bad = RewindExplanation(status: .needsClarification, kind: .word, spokenSummary: "Which word?", clarification: ClarificationPrompt(question: "Which word?", options: ["madi", " "]))
        #expect(throws: ExplanationValidationError.clarificationMissingOptions) { try validator.validate(bad) }

        let good = RewindExplanation(status: .needsClarification, kind: .word, spokenSummary: "Which word?", clarification: ClarificationPrompt(question: "Which word?", options: ["madi", "vishappu", "urakkam", "deshyam", "extra"]))
        #expect(try validator.validate(good).explanation.clarification?.options.count == 4)
    }

    @Test func dropsIncompleteItemsAndCapsCount() throws {
        var items = (0..<8).map { _ in item() }
        items.append(item(translit: "", meaning: ""))
        let e = RewindExplanation(status: .answered, kind: .gist, spokenSummary: "ok", items: items)
        let result = try validator.validate(e)
        #expect(result.explanation.items.count == ExplanationValidator.maxItems)
    }

    @Test func truncatesLongSummary() throws {
        let e = RewindExplanation(status: .uncertain, kind: .word, spokenSummary: String(repeating: "a", count: 1_000))
        #expect(try validator.validate(e).explanation.spokenSummary.count == ExplanationValidator.maxSummaryCharacters)
    }

    @Test func decodesBackendSnakeCaseJSON() throws {
        let json = """
        {
          "status": "needs_clarification",
          "kind": "word",
          "spoken_summary": "Did you mean madi or mazha?",
          "heard": null,
          "items": [],
          "suggested_replies": [],
          "grammar_note": null,
          "clarification": {"question": "Which word?", "options": ["madi", "mazha"]},
          "alternatives": [{"transliteration": "mazha", "english_meaning": "rain"}],
          "uncertainty_note": null
        }
        """
        let e = try LanguifyAPIClient.makeDecoder().decode(RewindExplanation.self, from: Data(json.utf8))
        #expect(e.status == .needsClarification)
        #expect(e.alternatives.first?.englishMeaning == "rain")
        #expect(try validator.validate(e).explanation.clarification?.options == ["madi", "mazha"])
    }
}

@Suite("QuestionKind")
struct QuestionKindTests {
    @Test(arguments: [
        ("What did that last word mean?", RewindQuestionKind.word),
        ("What was the word she just used?", .word),
        ("What does the word that sounded like madi mean?", .word),
        ("What did that last sentence mean?", .sentence),
        ("What does that expression mean?", .expression),
        ("How would I respond in Malayalam?", .respond),
        ("Can you explain what was just said?", .gist),
        ("Can you explain that sentence in simpler English?", .sentence),
        ("What is the difference between those two words?", .word),
        ("hmm", .auto),
    ])
    func infersKind(_ question: String, _ expected: RewindQuestionKind) {
        #expect(RewindQuestionKind.infer(from: question) == expected)
    }
}

@Suite("Plans and quotas")
struct PlanTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    @Test func freeTierQuotaExhausts() {
        let resolver = EntitlementResolver(catalog: .fallback, tier: .free)
        var ledger = UsageLedger()
        let now = Date()
        for _ in 0..<10 {
            guard case .allowed = resolver.check(.rewindQuestion, feature: .liveRewind, ledger: ledger, now: now, calendar: calendar) else {
                Issue.record("expected allowed"); return
            }
            ledger.record(.rewindQuestion, at: now, calendar: calendar)
        }
        #expect(resolver.check(.rewindQuestion, feature: .liveRewind, ledger: ledger, now: now, calendar: calendar) == .quotaExhausted(limit: 10))
    }

    @Test func ledgerResetsAtLocalMidnight() {
        var ledger = UsageLedger()
        let lateNight = DateComponents(calendar: calendar, year: 2026, month: 10, day: 21, hour: 23, minute: 59).date!
        ledger.record(.rewindQuestion, at: lateNight, calendar: calendar)
        #expect(ledger.used(.rewindQuestion) == 1)
        ledger.roll(to: lateNight.addingTimeInterval(120), calendar: calendar)
        #expect(ledger.used(.rewindQuestion) == 0)
        #expect(ledger.day == "2026-10-22")
    }

    @Test func premiumOnlyFeaturesAreLockedOnFree() {
        let free = EntitlementResolver(catalog: .fallback, tier: .free)
        #expect(free.check(.tutorTurn, feature: .conversationPractice, ledger: UsageLedger(), now: Date()) == .featureLocked(.conversationPractice))
        let premium = EntitlementResolver(catalog: .fallback, tier: .premium)
        #expect(premium.check(.tutorTurn, feature: .conversationPractice, ledger: UsageLedger(), now: Date()) == .allowed(remaining: 150))
    }

    @Test func premiumIsNeverUnlimited() {
        for action in MeteredAction.allCases {
            let limit = PlanCatalog.fallback.plan(.premium).dailyLimits[action]
            #expect(limit != nil && limit! > 0 && limit! < 10_000)
        }
    }

    @Test func catalogDecodesFromBackendJSON() throws {
        let json = """
        {"version": 3, "premium_product_ids": ["a"], "plans": {
          "free": {"tier": "free", "features": ["live_rewind"], "daily_limits": {"rewind_question": 5}},
          "premium": {"tier": "premium", "features": ["live_rewind", "conversation_practice"], "daily_limits": {"rewind_question": 100, "tutor_turn": 50}}
        }}
        """
        let catalog = try LanguifyAPIClient.makeDecoder().decode(PlanCatalog.self, from: Data(json.utf8))
        #expect(catalog.version == 3)
        #expect(catalog.plan(.free).dailyLimits[.rewindQuestion] == 5)
        #expect(catalog.plan(.premium).features.contains(.conversationPractice))
        // And back out with the same keys.
        let out = String(decoding: try LanguifyAPIClient.makeEncoder().encode(catalog), as: UTF8.self)
        #expect(out.contains("\"rewind_question\""))
        #expect(out.contains("\"premium_product_ids\""))
    }
}

@Suite("Preferences")
struct PreferenceTests {
    @Test func defaults() {
        let p = UserPreferences()
        #expect(p.rewindDuration == .sixtySeconds)
        #expect(p.cloudProcessingConsent == false)
        #expect(p.proactiveSuggestions == false)
    }

    @Test func neverSpeaksThroughSpeakerUnlessChosen() {
        #expect(!SpeechDeliveryPolicy.shouldSpeak(mode: .adaptive, headphonesConnected: false))
        #expect(SpeechDeliveryPolicy.shouldSpeak(mode: .adaptive, headphonesConnected: true))
        #expect(!SpeechDeliveryPolicy.shouldSpeak(mode: .headphonesOnly, headphonesConnected: false))
        #expect(!SpeechDeliveryPolicy.shouldSpeak(mode: .silent, headphonesConnected: true))
        #expect(SpeechDeliveryPolicy.shouldSpeak(mode: .spoken, headphonesConnected: false))
    }

    @Test func roundTrips() throws {
        var p = UserPreferences(language: .tamil)
        p.goals = [.buildSentences, .pronunciation]
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(UserPreferences.self, from: data) == p)
    }

    @Test func scriptDetection() {
        let ta = HeritageLanguage.tamil.configuration
        #expect(ta.containsNativeScript("நான் office போறேன்"))
        #expect(!ta.containsNativeScript("naan office poren"))
        #expect(!HeritageLanguage.malayalam.configuration.containsNativeScript("நான்"))
        #expect(ta.nativeScriptRatio("நான்") == 1)
    }
}
