import Foundation
import LanguifyKit

/// A small, hand-checked set of everyday words per language, used by the
/// optional assessment and when the journal is still empty. Colloquial
/// spoken forms are used where they differ from the written form.
enum StarterWords {
    struct Word: Hashable {
        let nativeScript: String
        let transliteration: String
        let english: String
    }

    static func words(for language: HeritageLanguage) -> [Word] {
        switch language {
        case .tamil:
            [
                Word(nativeScript: "தண்ணீர்", transliteration: "thanneer", english: "water"),
                Word(nativeScript: "சாப்பாடு", transliteration: "saappaadu", english: "food, a meal"),
                Word(nativeScript: "வீடு", transliteration: "veedu", english: "house, home"),
                Word(nativeScript: "நாளைக்கு", transliteration: "naalaikku", english: "tomorrow"),
                Word(nativeScript: "இன்னைக்கு", transliteration: "innaikku", english: "today"),
                Word(nativeScript: "தூக்கம்", transliteration: "thookkam", english: "sleep"),
                Word(nativeScript: "பசி", transliteration: "pasi", english: "hunger"),
                Word(nativeScript: "சந்தோஷம்", transliteration: "santhosham", english: "happiness"),
                Word(nativeScript: "வேலை", transliteration: "velai", english: "work, job"),
                Word(nativeScript: "பள்ளிக்கூடம்", transliteration: "pallikkoodam", english: "school"),
            ]
        case .malayalam:
            [
                Word(nativeScript: "വെള്ളം", transliteration: "vellam", english: "water"),
                Word(nativeScript: "ചോറ്", transliteration: "choru", english: "cooked rice, a meal"),
                Word(nativeScript: "വീട്", transliteration: "veedu", english: "house, home"),
                Word(nativeScript: "നാളെ", transliteration: "naale", english: "tomorrow"),
                Word(nativeScript: "ഇന്ന്", transliteration: "innu", english: "today"),
                Word(nativeScript: "ഉറക്കം", transliteration: "urakkam", english: "sleep"),
                Word(nativeScript: "വിശപ്പ്", transliteration: "vishappu", english: "hunger"),
                Word(nativeScript: "സന്തോഷം", transliteration: "santhosham", english: "happiness"),
                Word(nativeScript: "ജോലി", transliteration: "joli", english: "work, job"),
                Word(nativeScript: "പഠിത്തം", transliteration: "padiththam", english: "studies, learning"),
            ]
        }
    }
}

/// Anything the learner can practise saying.
struct PracticeTarget: Hashable {
    let nativeScript: String
    let transliteration: String
    let english: String
    let entryID: UUID?

    init(nativeScript: String, transliteration: String, english: String, entryID: UUID? = nil) {
        self.nativeScript = nativeScript
        self.transliteration = transliteration
        self.english = english
        self.entryID = entryID
    }

    init(entry: VocabularyEntry) {
        self.init(nativeScript: entry.nativeScript, transliteration: entry.transliteration, english: entry.englishMeaning, entryID: entry.id)
    }

    init(word: StarterWords.Word) {
        self.init(nativeScript: word.nativeScript, transliteration: word.transliteration, english: word.english)
    }

    var speakable: String { nativeScript.isEmpty ? transliteration : nativeScript }
}

