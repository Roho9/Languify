import Foundation
import LanguifyKit
@testable import Languify

// TEST DOUBLES. Used only by the unit tests in this target.

/// Audio source with a canned snapshot, standing in for a live microphone.
final class FakeAudioSource: RewindAudioSource {
    var isSessionActive = true
    var audio = AudioSnapshot(samples: Array(repeating: 0.2, count: 16_000 * 5), sampleRate: 16_000)
    private(set) var processingCount = 0

    func snapshot(lastSeconds: Double, endingAt: TimeInterval) -> AudioSnapshot { audio }
    func beginProcessing() { processingCount += 1 }
    func endProcessing(answer: String?) {}
}

/// Returns fixed segments per locale.
nonisolated struct FakeTranscriber: SpeechTranscribing {
    var byLocale: [String: [TranscriptSegment]] = [:]
    var error: TranscriptionError?

    func transcribe(_ snapshot: AudioSnapshot, localeIdentifier: String) async throws -> [TranscriptSegment] {
        if let error { throw error }
        return byLocale[localeIdentifier] ?? []
    }
}

nonisolated struct FixedToken: AuthTokenProviding {
    func currentToken() async throws -> String { "test-token" }
    func invalidate() async {}
}

/// Intercepts URLSession requests and replies with a scripted response.
nonisolated final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@MainActor
struct RewindHarness {
    let audio = FakeAudioSource()
    let preferences: PreferencesStore
    let repository: VocabularyRepository
    let service: LiveRewindService

    init(transcriber: FakeTranscriber, consent: Bool = true) {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        preferences = PreferencesStore(defaults: defaults)
        preferences.preferences.language = .malayalam
        preferences.preferences.cloudProcessingConsent = consent
        let api = LanguifyAPIClient(baseURL: URL(string: "https://api.test")!, session: StubURLProtocol.session(), tokens: FixedToken())
        let container = LanguifySchema.makeContainer(syncWithICloud: false, inMemory: true)
        let repository = VocabularyRepository(context: container.mainContext)
        self.repository = repository
        let audioSession = AudioSessionController()
        service = LiveRewindService(
            session: audio,
            transcriber: transcriber,
            api: api,
            preferences: preferences,
            delivery: ResponseDelivery(audioSession: audioSession, preferences: preferences),
            subscriptions: SubscriptionStore(api: api),
            repository: { repository }
        )
        _container = container
    }

    // Keeps the in-memory store alive for the harness lifetime.
    private let _container: Any
}

enum Fixtures {
    static let malayalamSegments = [
        TranscriptSegment(text: "avanu bhayankara madi aanu", start: 0, end: 2.2, confidence: 0.82, alternatives: []),
    ]

    static let heardJSON = #"{"native_script":"അവന് ഭയങ്കര മടിയാണ്","transliteration":"avanu bhayankara madiyaanu","english_natural":"He is really lazy.","literal_gloss":null}"#

    static func explanationJSON(status: String = "answered", clarification: String = "null", items: String? = nil, heard: String = heardJSON) -> Data {
        let defaultItems = """
        [{"native_script":"മടി","transliteration":"madi","english_meaning":"laziness","contextual_meaning":"he is very lazy","pronunciation_hint":"MA-di","part_of_speech":"noun","register":"informal","usage_note":null,"cultural_note":null,"regional_note":null,"example":{"native_script":"എനിക്ക് മടിയാണ്","transliteration":"enikku madiyaanu","english":"I feel lazy"},"related":[]}]
        """
        return Data("""
        {"status":"\(status)","kind":"word","spoken_summary":"Madi means laziness. They said he is very lazy.",
         "heard":\(heard),
         "items":\(items ?? defaultItems),"suggested_replies":[],"grammar_note":null,"clarification":\(clarification),"alternatives":[],"uncertainty_note":null}
        """.utf8)
    }
}
