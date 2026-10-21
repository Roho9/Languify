import Foundation

public enum RewindDuration: Int, Codable, CaseIterable, Sendable, Identifiable {
    case thirtySeconds = 30
    case sixtySeconds = 60
    case twoMinutes = 120

    public static let `default`: RewindDuration = .sixtySeconds

    public var id: Int { rawValue }
    public var seconds: Double { Double(rawValue) }
    public var label: String {
        switch self {
        case .thirtySeconds: "30 seconds"
        case .sixtySeconds: "60 seconds"
        case .twoMinutes: "2 minutes"
        }
    }
}

/// How explanations are delivered.
public enum ResponseMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Speak privately through headphones when connected; otherwise show on screen only.
    case adaptive
    /// Always on screen, never spoken.
    case silent
    /// Speak through whatever output is active, including the iPhone speaker.
    case spoken
    /// Speak only when headphones are connected (same as adaptive, but stated explicitly).
    case headphonesOnly

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .adaptive: "Adaptive"
        case .silent: "Silent"
        case .spoken: "Spoken"
        case .headphonesOnly: "AirPods only"
        }
    }
    public var detail: String {
        switch self {
        case .adaptive: "Speaks privately when headphones are connected, otherwise shows the answer on screen."
        case .silent: "Shows the answer on screen without speaking."
        case .spoken: "Speaks through the current output, including the iPhone speaker."
        case .headphonesOnly: "Speaks only through headphones. Never uses the speaker."
        }
    }
}

/// Which representation of a word appears first on cards and explanations.
public enum ScriptDisplay: String, Codable, CaseIterable, Sendable, Identifiable {
    case transliterationFirst
    case nativeScriptFirst
    case englishFirst

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .transliterationFirst: "Transliteration first"
        case .nativeScriptFirst: "Native script first"
        case .englishFirst: "English first"
        }
    }
}

public enum SkillFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    case understandsMostly
    case speaksSome
    case reads
    case writes

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .understandsMostly: "I understand it"
        case .speaksSome: "I can speak some"
        case .reads: "I can read the script"
        case .writes: "I can write the script"
        }
    }
}

public enum LearningGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case talkWithFamily
    case speakWithGrandparents
    case understandUncommonWords
    case buildSentences
    case pronunciation
    case confidence
    case culturalConversations

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .talkWithFamily: "Reply to family in the language"
        case .speakWithGrandparents: "Talk with grandparents"
        case .understandUncommonWords: "Understand uncommon words"
        case .buildSentences: "Build full sentences"
        case .pronunciation: "Improve pronunciation"
        case .confidence: "Feel confident speaking"
        case .culturalConversations: "Join cultural conversations"
        }
    }
}

/// Self-assessed level on a 1 to 5 scale.
public struct SelfRating: Codable, Equatable, Sendable {
    public var comprehension: Int
    public var speaking: Int
    public var reading: Int

    public init(comprehension: Int = 4, speaking: Int = 2, reading: Int = 1) {
        self.comprehension = Self.clamp(comprehension)
        self.speaking = Self.clamp(speaking)
        self.reading = Self.clamp(reading)
    }

    static func clamp(_ value: Int) -> Int { min(5, max(1, value)) }
}

/// All user-adjustable preferences. Persisted locally as JSON.
public struct UserPreferences: Codable, Equatable, Sendable {
    public var language: HeritageLanguage
    public var skills: Set<SkillFocus>
    public var selfRating: SelfRating
    public var goals: Set<LearningGoal>
    public var scriptDisplay: ScriptDisplay
    public var showNativeScript: Bool
    public var responseMode: ResponseMode
    public var rewindDuration: RewindDuration
    public var autoSaveVocabulary: Bool
    /// Consent to send transcribed text (never audio) to Languify's AI service.
    public var cloudProcessingConsent: Bool
    /// Opt-in: analyse a session's speech after it ends to suggest words.
    public var proactiveSuggestions: Bool
    public var dailyReminder: Bool
    public var reminderHour: Int
    public var hasCompletedOnboarding: Bool

    public init(
        language: HeritageLanguage = .malayalam,
        skills: Set<SkillFocus> = [.understandsMostly],
        selfRating: SelfRating = SelfRating(),
        goals: Set<LearningGoal> = [.talkWithFamily],
        scriptDisplay: ScriptDisplay = .transliterationFirst,
        showNativeScript: Bool = true,
        responseMode: ResponseMode = .adaptive,
        rewindDuration: RewindDuration = .default,
        autoSaveVocabulary: Bool = true,
        cloudProcessingConsent: Bool = false,
        proactiveSuggestions: Bool = false,
        dailyReminder: Bool = false,
        reminderHour: Int = 19,
        hasCompletedOnboarding: Bool = false
    ) {
        self.language = language
        self.skills = skills
        self.selfRating = selfRating
        self.goals = goals
        self.scriptDisplay = scriptDisplay
        self.showNativeScript = showNativeScript
        self.responseMode = responseMode
        self.rewindDuration = rewindDuration
        self.autoSaveVocabulary = autoSaveVocabulary
        self.cloudProcessingConsent = cloudProcessingConsent
        self.proactiveSuggestions = proactiveSuggestions
        self.dailyReminder = dailyReminder
        self.reminderHour = reminderHour
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

/// Decides whether an explanation should be spoken, given the mode and the
/// current audio route. Kept pure so the privacy rule is unit tested:
/// nothing is spoken through the speaker unless the user chose `.spoken`.
public enum SpeechDeliveryPolicy {
    public static func shouldSpeak(mode: ResponseMode, headphonesConnected: Bool) -> Bool {
        switch mode {
        case .silent: false
        case .spoken: true
        case .adaptive, .headphonesOnly: headphonesConnected
        }
    }
}
