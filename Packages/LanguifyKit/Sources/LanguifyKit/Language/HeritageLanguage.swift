import Foundation

/// A heritage language Languify can teach.
///
/// Adding a language means adding a case and its `LanguageConfiguration`.
/// Speech, transliteration, synthesis and lesson generation all read from the
/// configuration, so no feature code switches on specific languages.
public enum HeritageLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case tamil = "ta"
    case malayalam = "ml"

    public var id: String { rawValue }

    public var configuration: LanguageConfiguration {
        switch self {
        case .tamil:
            LanguageConfiguration(
                code: "ta",
                englishName: "Tamil",
                nativeName: "தமிழ்",
                speechLocaleIdentifier: "ta-IN",
                synthesisLanguageCode: "ta-IN",
                scriptName: "Tamil script",
                scriptRange: 0x0B80...0x0BFF,
                sampleGreetingNative: "வணக்கம்",
                sampleGreetingTransliteration: "vaṇakkam"
            )
        case .malayalam:
            LanguageConfiguration(
                code: "ml",
                englishName: "Malayalam",
                nativeName: "മലയാളം",
                speechLocaleIdentifier: "ml-IN",
                synthesisLanguageCode: "ml-IN",
                scriptName: "Malayalam script",
                scriptRange: 0x0D00...0x0D7F,
                sampleGreetingNative: "നമസ്കാരം",
                sampleGreetingTransliteration: "namaskāram"
            )
        }
    }

    public var displayName: String { configuration.englishName }
}

/// Static, per-language configuration consumed by language-agnostic services.
public struct LanguageConfiguration: Sendable, Hashable {
    public let code: String
    public let englishName: String
    public let nativeName: String
    /// BCP 47 locale passed to Apple's `SpeechTranscriber`.
    public let speechLocaleIdentifier: String
    /// BCP 47 code used to look up an `AVSpeechSynthesisVoice`.
    public let synthesisLanguageCode: String
    public let scriptName: String
    /// Unicode block of the native script, used to validate AI output.
    public let scriptRange: ClosedRange<UInt32>
    public let sampleGreetingNative: String
    public let sampleGreetingTransliteration: String

    /// English is always transcribed alongside the heritage language so that
    /// code-switched speech has a second hypothesis to reconcile against.
    public static let companionEnglishLocaleIdentifier = "en-IN"

    /// True when `text` contains at least one character of this language's script.
    public func containsNativeScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scriptRange.contains($0.value) }
    }

    /// Fraction of letters in `text` that belong to this script (ignores
    /// whitespace, digits and punctuation).
    public func nativeScriptRatio(_ text: String) -> Double {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic || scriptRange.contains($0.value) }
        guard !letters.isEmpty else { return 0 }
        let native = letters.filter { scriptRange.contains($0.value) }.count
        return Double(native) / Double(letters.count)
    }
}
