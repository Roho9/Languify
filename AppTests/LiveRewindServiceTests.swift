import Foundation
import LanguifyKit
import Testing
@testable import Languify

/// Integration tests for the pipeline: audio snapshot -> transcription ->
/// explanation request -> validation -> vocabulary journal.
@MainActor
@Suite(.serialized)
struct LiveRewindServiceTests {
    init() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastBody = nil
    }

    func transcriber() -> FakeTranscriber {
        FakeTranscriber(byLocale: ["ml-IN": Fixtures.malayalamSegments, "en-IN": []])
    }

    @Test func answersAndSavesVocabulary() async throws {
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON()) }
        let h = RewindHarness(transcriber: transcriber())
        let outcome = await h.service.ask(RewindQuery(question: "What did that last word mean?", kind: .word, speakAnswer: false))

        guard case .answered(let answer) = outcome else {
            Issue.record("Expected an answer, got \(outcome)")
            return
        }
        #expect(answer.explanation.items.first?.transliteration == "madi")
        #expect(answer.savedEntryIDs.count == 1)
        let saved = h.repository.entries()
        #expect(saved.count == 1)
        #expect(saved.first?.contextSentence == "avanu bhayankara madiyaanu")
        #expect(saved.first?.contextTranslation == "He is really lazy.")
        #expect(h.preferences.ledger.used(.rewindQuestion) == 1)
        #expect(h.service.recentAnswers.count == 1)
        #expect(h.audio.processingCount == 1)

        // Only text was sent: the request carries the transcript, no audio.
        let body = try #require(StubURLProtocol.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let transcript = try #require(json["transcript"] as? [String: Any])
        #expect((transcript["primary"] as? [[String: Any]])?.first?["text"] as? String == "avanu bhayankara madi aanu")
        #expect(json["language"] as? String == "ml")
        #expect(String(decoding: body, as: UTF8.self).contains("samples") == false)
    }

    @Test func askingTwiceMergesTheEntry() async {
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON()) }
        let h = RewindHarness(transcriber: transcriber())
        _ = await h.service.ask(RewindQuery(question: "word?", kind: .word, speakAnswer: false))
        _ = await h.service.ask(RewindQuery(question: "word?", kind: .word, speakAnswer: false))
        let entries = h.repository.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.encounterCount == 2)
    }

    @Test func notListeningWithoutSession() async {
        let h = RewindHarness(transcriber: transcriber())
        h.audio.isSessionActive = false
        #expect(await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) == .notListening)
    }

    @Test func silenceNeverReachesTheCloud() async {
        var called = false
        StubURLProtocol.handler = { _ in called = true; return (200, Fixtures.explanationJSON()) }
        let h = RewindHarness(transcriber: transcriber())
        h.audio.audio = AudioSnapshot(samples: Array(repeating: 0, count: 16_000 * 5), sampleRate: 16_000)
        #expect(await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) == .noSpeech)
        #expect(!called)
    }

    @Test func emptyTranscriptIsNoSpeech() async {
        let h = RewindHarness(transcriber: FakeTranscriber())
        #expect(await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) == .noSpeech)
    }

    @Test func withoutConsentOnlyTranscribes() async {
        var called = false
        StubURLProtocol.handler = { _ in called = true; return (200, Fixtures.explanationJSON()) }
        let h = RewindHarness(transcriber: transcriber(), consent: false)
        let outcome = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false))
        guard case .needsCloudConsent(let transcript) = outcome else {
            Issue.record("Expected consent prompt"); return
        }
        #expect(transcript.primaryText == "avanu bhayankara madi aanu")
        #expect(!called)
    }

    @Test func missingSpeechModelIsReported() async {
        let h = RewindHarness(transcriber: FakeTranscriber(error: .modelNotInstalled("ml-IN")))
        #expect(await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) == .speechModelMissing)
    }

    @Test func clarificationKeepsTheTranscriptForTheFollowUp() async {
        StubURLProtocol.handler = { _ in
            (200, Fixtures.explanationJSON(status: "needs_clarification", clarification: #"{"question":"Which word?","options":["madi","bhayankara"]}"#, items: "[]"))
        }
        let h = RewindHarness(transcriber: transcriber())
        let outcome = await h.service.ask(RewindQuery(question: "that word?", kind: .word, speakAnswer: false))
        guard case .needsClarification(let prompt, let followUp) = outcome else {
            Issue.record("Expected clarification"); return
        }
        #expect(prompt.options == ["madi", "bhayankara"])
        #expect(followUp.transcript?.primaryText == "avanu bhayankara madi aanu")
        #expect(h.repository.entries().isEmpty)

        // The follow-up reuses the transcript even after the session ends.
        h.audio.isSessionActive = false
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON()) }
        var next = followUp
        next.clarification = ClarificationAnswer(question: prompt.question, chosenOption: "madi")
        guard case .answered = await h.service.ask(next) else {
            Issue.record("Expected answer after clarification"); return
        }
        let body = String(decoding: StubURLProtocol.lastBody ?? Data(), as: UTF8.self)
        #expect(body.contains("\"chosen_option\":\"madi\""))
    }

    @Test func uncertainAnswersAreNotAutoSaved() async {
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON(status: "uncertain")) }
        let h = RewindHarness(transcriber: transcriber())
        guard case .answered(let answer) = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("Expected answer"); return
        }
        #expect(answer.savedEntryIDs.isEmpty)
        #expect(h.repository.entries().isEmpty)
        #expect(h.service.saveConfirmed(answer).count == 1)
    }

    @Test func serverQuotaIsSurfaced() async {
        StubURLProtocol.handler = { _ in (402, Data(#"{"error":"quota_exceeded","action":"rewind_question","limit":10,"resets_at":"2026-10-22T00:00:00Z"}"#.utf8)) }
        let h = RewindHarness(transcriber: transcriber())
        let outcome = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false))
        guard case .quotaExceeded(let resetsAt) = outcome else {
            Issue.record("Expected quota, got \(outcome)"); return
        }
        #expect(resetsAt != nil)
    }

    @Test func localQuotaBlocksBeforeTheRequest() async {
        var called = false
        StubURLProtocol.handler = { _ in called = true; return (200, Fixtures.explanationJSON()) }
        let h = RewindHarness(transcriber: transcriber())
        for _ in 0..<10 { h.preferences.ledger.record(.rewindQuestion, at: Date()) }
        guard case .quotaExceeded = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("Expected quota"); return
        }
        #expect(!called)
    }

    @Test func offlineKeepsTranscriptForRetry() async {
        StubURLProtocol.handler = nil
        let h = RewindHarness(transcriber: transcriber())
        guard case .failed(_, let transcript, let retryable) = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("Expected failure"); return
        }
        #expect(transcript != nil)
        #expect(retryable)
    }

    @Test func invalidAIOutputIsRejected() async {
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON(items: "[]", heard: "null")) }
        let h = RewindHarness(transcriber: transcriber())
        guard case .failed = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("Expected validation failure"); return
        }
        #expect(h.repository.entries().isEmpty)
    }
}
