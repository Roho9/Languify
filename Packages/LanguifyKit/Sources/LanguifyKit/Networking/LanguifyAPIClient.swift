import Foundation

/// Errors surfaced by the Languify backend client, mapped to cases the UI can
/// explain. Raw server messages are never shown verbatim.
public enum APIError: Error, Equatable, Sendable {
    case notConfigured
    case offline
    case timedOut
    case unauthorized
    case quotaExceeded(action: String, resetsAt: Date?)
    case featureLocked(String)
    case rateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case invalidResponse
    case server(status: Int)

    public var userMessage: String {
        switch self {
        case .notConfigured: "Languify's AI service isn't configured in this build."
        case .offline: "You're offline. Your transcript is saved on this device; try again when you're connected."
        case .timedOut: "The AI service took too long to answer. Try again."
        case .unauthorized: "Languify couldn't verify this device. Try again in a moment."
        case .quotaExceeded: "You've used today's free questions."
        case .featureLocked: "This is a Premium feature."
        case .rateLimited: "Too many requests at once. Wait a few seconds and try again."
        case .serviceUnavailable: "The AI service is temporarily unavailable."
        case .invalidResponse: "The AI service returned something Languify couldn't use."
        case .server: "Something went wrong on Languify's server."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited, .serviceUnavailable, .server: true
        default: false
        }
    }
}

/// Supplies and refreshes the bearer token for API calls.
public protocol AuthTokenProviding: Sendable {
    func currentToken() async throws -> String
    /// Called after a 401 so the provider can obtain a fresh token.
    func invalidate() async
}

// MARK: - Wire types

public struct InstallRegistration: Codable, Sendable {
    public var installId: String
    public init(installId: String) { self.installId = installId }
}

public struct TokenResponse: Codable, Sendable, Equatable {
    public var token: String
    public var expiresAt: Date
    public var userId: String?
}

public struct AppleLinkRequest: Codable, Sendable {
    public var identityToken: String
    public init(identityToken: String) { self.identityToken = identityToken }
}

public struct EntitlementRequest: Codable, Sendable {
    public var signedTransactions: [String]
    public init(signedTransactions: [String]) { self.signedTransactions = signedTransactions }
}

public struct EntitlementResponse: Codable, Sendable, Equatable {
    public var tier: PlanTier
    public var expiresAt: Date?
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var tier: PlanTier
    public var day: String
    public var used: [MeteredAction: Int]
    public var limits: [MeteredAction: Int]
}

public struct TutorTurnRequest: Codable, Sendable {
    public var language: HeritageLanguage
    public var scenario: String
    public var history: [TutorMessage]
    /// What the recogniser heard the learner say (romanised).
    public var learnerUtterance: String
    public var learnerUtteranceConfidence: Double?
    public var learner: LearnerSnapshot

    public init(language: HeritageLanguage, scenario: String, history: [TutorMessage], learnerUtterance: String, learnerUtteranceConfidence: Double?, learner: LearnerSnapshot) {
        self.language = language
        self.scenario = scenario
        self.history = history
        self.learnerUtterance = learnerUtterance
        self.learnerUtteranceConfidence = learnerUtteranceConfidence
        self.learner = learner
    }
}

public struct TutorMessage: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable { case tutor, learner }
    public var id: UUID
    public var role: Role
    public var transliteration: String
    public var nativeScript: String
    public var english: String

    public init(id: UUID = UUID(), role: Role, transliteration: String, nativeScript: String = "", english: String = "") {
        self.id = id
        self.role = role
        self.transliteration = transliteration
        self.nativeScript = nativeScript
        self.english = english
    }
}

public struct TutorTurnResponse: Codable, Sendable, Equatable {
    public var reply: LocalizedPhrase
    /// A more natural way to say what the learner meant, if it needs one.
    public var correction: TutorCorrection?
    public var encouragement: String
    public var assessment: TutorAssessment
}

public struct TutorCorrection: Codable, Sendable, Equatable {
    public var natural: LocalizedPhrase
    public var explanation: String
}

/// Tutor's rating of the learner's turn. These are model judgements from
/// text, labelled as estimates in the UI, not calibrated measurements.
public struct TutorAssessment: Codable, Sendable, Equatable {
    public var fluency: Double
    public var grammar: Double
    public var completeSentence: Bool
    public var usedEnglish: Bool
}

public struct SuggestionsRequest: Codable, Sendable {
    public var language: HeritageLanguage
    public var transcript: RewindTranscript
    public var learner: LearnerSnapshot
    public var knownWords: [String]

    public init(language: HeritageLanguage, transcript: RewindTranscript, learner: LearnerSnapshot, knownWords: [String]) {
        self.language = language
        self.transcript = transcript
        self.learner = learner
        self.knownWords = Array(knownWords.prefix(200))
    }
}

public struct SuggestionsResponse: Codable, Sendable, Equatable {
    public var items: [VocabularyExplanation]
}

public struct LessonRequest: Codable, Sendable {
    public var language: HeritageLanguage
    public var focus: SkillDimension
    public var words: [LessonWord]
    public var learner: LearnerSnapshot

    public init(language: HeritageLanguage, focus: SkillDimension, words: [LessonWord], learner: LearnerSnapshot) {
        self.language = language
        self.focus = focus
        self.words = Array(words.prefix(15))
        self.learner = learner
    }
}

public struct LessonWord: Codable, Sendable, Equatable {
    public var transliteration: String
    public var english: String
    public var context: String?

    public init(transliteration: String, english: String, context: String?) {
        self.transliteration = transliteration
        self.english = english
        self.context = context
    }
}

public struct Lesson: Codable, Sendable, Equatable {
    public var title: String
    public var goal: String
    public var steps: [LessonStep]
}

public struct LessonStep: Codable, Sendable, Equatable, Identifiable {
    public var id: String { prompt + (model?.transliteration ?? "") }
    public enum Kind: String, Codable, Sendable {
        case explain, listenAndRepeat = "listen_and_repeat", buildSentence = "build_sentence", speakPrompt = "speak_prompt"
    }
    public var kind: Kind
    public var prompt: String
    public var model: LocalizedPhrase?
    public var tip: String?
}

// MARK: - Client

/// Thin, typed client for the Languify backend. All AI provider calls go
/// through the backend; the app never holds provider credentials.
public final class LanguifyAPIClient: Sendable {
    public let baseURL: URL?
    private let session: URLSession
    private let tokens: AuthTokenProviding?

    public init(baseURL: URL?, session: URLSession = .shared, tokens: AuthTokenProviding?) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // Unauthenticated
    public func registerInstall(_ body: InstallRegistration) async throws -> TokenResponse {
        try await send("POST", "/v1/auth/install", body: body, authenticated: false)
    }

    public func fetchCatalog() async throws -> PlanCatalog {
        try await send("GET", "/v1/config", body: Optional<Int>.none, authenticated: false)
    }

    // Authenticated
    public func linkApple(_ body: AppleLinkRequest) async throws -> TokenResponse {
        try await send("POST", "/v1/auth/apple", body: body)
    }

    /// Generous timeouts: a local open-weight model (Ollama) takes about
    /// 15 to 20 s per explanation on Apple silicon, longer on a cold start.
    public func explain(_ body: RewindExplainRequest, timeout: TimeInterval = 60) async throws -> RewindExplanation {
        try await send("POST", "/v1/rewind/explain", body: body, timeout: timeout)
    }

    public func tutorTurn(_ body: TutorTurnRequest) async throws -> TutorTurnResponse {
        try await send("POST", "/v1/tutor/turn", body: body, timeout: 60)
    }

    public func suggestions(_ body: SuggestionsRequest) async throws -> SuggestionsResponse {
        try await send("POST", "/v1/suggestions", body: body, timeout: 90)
    }

    public func lesson(_ body: LessonRequest) async throws -> Lesson {
        try await send("POST", "/v1/lessons", body: body, timeout: 90)
    }

    public func verifyEntitlements(_ body: EntitlementRequest) async throws -> EntitlementResponse {
        try await send("POST", "/v1/entitlements/verify", body: body)
    }

    public func usage() async throws -> UsageSnapshot {
        try await send("GET", "/v1/usage", body: Optional<Int>.none)
    }

    public func deleteAccount() async throws {
        let _: EmptyResponse = try await send("DELETE", "/v1/account", body: Optional<Int>.none)
    }

    struct EmptyResponse: Decodable {}

    struct ErrorBody: Decodable {
        var error: String
        var action: String?
        var resetsAt: Date?
        var feature: String?
    }

    func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ path: String,
        body: Body?,
        authenticated: Bool = true,
        timeout: TimeInterval = 30,
        isRetry: Bool = false
    ) async throws -> Response {
        guard let baseURL else { throw APIError.notConfigured }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try Self.makeEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let tokens else { throw APIError.unauthorized }
            request.setValue("Bearer \(try await tokens.currentToken())", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost:
                throw APIError.offline
            case .timedOut:
                throw APIError.timedOut
            default:
                throw APIError.server(status: -1)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            if Response.self == EmptyResponse.self, data.isEmpty, let empty = EmptyResponse() as? Response { return empty }
            do { return try Self.makeDecoder().decode(Response.self, from: data) } catch { throw APIError.invalidResponse }
        case 401 where authenticated && !isRetry:
            await tokens?.invalidate()
            return try await send(method, path, body: body, authenticated: authenticated, timeout: timeout, isRetry: true)
        case 401:
            throw APIError.unauthorized
        case 402, 403:
            let err = try? Self.makeDecoder().decode(ErrorBody.self, from: data)
            if err?.error == "quota_exceeded" {
                throw APIError.quotaExceeded(action: err?.action ?? "", resetsAt: err?.resetsAt)
            }
            throw APIError.featureLocked(err?.feature ?? "")
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retry)
        case 502, 503, 504:
            throw APIError.serviceUnavailable
        default:
            throw APIError.server(status: http.statusCode)
        }
    }
}
