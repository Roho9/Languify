import Foundation
import LanguifyKit
import Testing
@testable import Languify

/// Fault-injection tests for the rewind pipeline. Each scenario must end in a
/// defined outcome with the right user-facing state, never a crash or a hang.
@MainActor
@Suite(.serialized)
struct ReliabilityTests {
    init() {
        StubURLProtocol.handler = nil
    }

    func transcriber() -> FakeTranscriber {
        FakeTranscriber(byLocale: ["ml-IN": Fixtures.malayalamSegments, "en-IN": []])
    }

    @Test func competingRequestsBothComplete() async {
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON()) }
        let h = RewindHarness(transcriber: transcriber())
        async let first = h.service.ask(RewindQuery(question: "word?", kind: .word, speakAnswer: false))
        async let second = h.service.ask(RewindQuery(question: "sentence?", kind: .sentence, speakAnswer: false))
        let outcomes = await [first, second]
        #expect(outcomes.allSatisfy { if case .answered = $0 { true } else { false } })
        #expect(h.service.recentAnswers.count == 2)
        // The same word asked twice is merged, not duplicated.
        #expect(h.repository.entries().count == 1)
        #expect(!h.service.isWorking)
    }

    @Test func timeoutIsRetryableAndKeepsTranscript() async {
        StubURLProtocol.handler = { _ in (504, Data()) }
        let h = RewindHarness(transcriber: transcriber())
        guard case .failed(let message, let transcript, let retryable) = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("expected failure"); return
        }
        #expect(retryable)
        #expect(transcript != nil)
        #expect(message == APIError.serviceUnavailable.userMessage)
        #expect(h.preferences.ledger.used(.rewindQuestion) == 0)
    }

    @Test func rateLimitIsRetryable() async {
        StubURLProtocol.handler = { _ in (429, Data()) }
        let h = RewindHarness(transcriber: transcriber())
        guard case .failed(_, _, let retryable) = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("expected failure"); return
        }
        #expect(retryable)
    }

    @Test func busyServerIsRetryable() async {
        StubURLProtocol.handler = { _ in (503, Data(#"{"error":"busy"}"#.utf8)) }
        let h = RewindHarness(transcriber: transcriber())
        guard case .failed(_, _, let retryable) = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("expected failure"); return
        }
        #expect(retryable)
    }

    @Test func truncatedJSONIsRejectedSafely() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"status":"answered","kind":"word","spoken_summ"#.utf8)) }
        let h = RewindHarness(transcriber: transcriber())
        guard case .failed = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("expected failure"); return
        }
        #expect(h.repository.entries().isEmpty)
    }

    @Test func recoveryAfterFailure() async {
        let h = RewindHarness(transcriber: transcriber())
        StubURLProtocol.handler = { _ in (503, Data()) }
        _ = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false))
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON()) }
        guard case .answered = await h.service.ask(RewindQuery(question: "q", kind: .word, speakAnswer: false)) else {
            Issue.record("expected recovery"); return
        }
        #expect(h.repository.entries().count == 1)
    }

    @Test func manyRapidRequestsStayConsistent() async {
        StubURLProtocol.handler = { _ in (200, Fixtures.explanationJSON()) }
        let h = RewindHarness(transcriber: transcriber())
        await withTaskGroup(of: RewindOutcome.self) { group in
            for i in 0..<10 {
                group.addTask { await h.service.ask(RewindQuery(question: "q\(i)", kind: .word, speakAnswer: false)) }
            }
        }
        #expect(h.service.recentAnswers.count == 10)
        #expect(h.repository.entries().count == 1)
        #expect(h.repository.entries().first?.encounterCount == 10)
        #expect(h.preferences.ledger.used(.rewindQuestion) == 10)
    }
}
