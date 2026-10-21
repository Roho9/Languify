import Foundation

/// Compares what the recogniser heard against the target phrase.
///
/// This is intelligibility feedback, not phoneme-level assessment: no
/// validated phoneme scorer exists for Tamil or Malayalam on Apple platforms.
/// Because Apple's Tamil and Malayalam recognisers emit romanised text, both
/// sides are compared as normalised romanisations, which tolerates the common
/// spelling variants (ae/e, oo/u, th/t and so on).
public struct PronunciationScorer: Sendable {
    public init() {}

    public enum Verdict: String, Sendable, Equatable {
        case recognized
        case close
        case different
        case nothingHeard

        public var headline: String {
            switch self {
            case .recognized: "Clearly understood"
            case .close: "Almost there"
            case .different: "Heard something different"
            case .nothingHeard: "Didn't catch that"
            }
        }
    }

    public struct WordResult: Sendable, Equatable {
        public let target: String
        public let heard: String?
        public let matched: Bool
    }

    public struct Result: Sendable, Equatable {
        /// Normalised similarity in [0, 1] between target and heard text.
        public let similarity: Double
        public let verdict: Verdict
        public let words: [WordResult]
        public let heardText: String
    }

    public func score(target: String, heard: String) -> Result {
        let targetWords = Self.words(target)
        let heardWords = Self.words(heard)
        guard !heardWords.isEmpty else {
            return Result(similarity: 0, verdict: .nothingHeard, words: targetWords.map { WordResult(target: $0, heard: nil, matched: false) }, heardText: heard)
        }
        let a = targetWords.map(Self.normalize).joined()
        let b = heardWords.map(Self.normalize).joined()
        let similarity = Self.similarity(a, b)

        // Greedy alignment: each target word takes the best unused heard word.
        var used = Set<Int>()
        let words = targetWords.map { word -> WordResult in
            let n = Self.normalize(word)
            var best: (Int, Double)?
            for (i, h) in heardWords.enumerated() where !used.contains(i) {
                let s = Self.similarity(n, Self.normalize(h))
                if s > (best?.1 ?? 0) { best = (i, s) }
            }
            if let best, best.1 >= 0.75 {
                used.insert(best.0)
                return WordResult(target: word, heard: heardWords[best.0], matched: true)
            }
            return WordResult(target: word, heard: best.map { heardWords[$0.0] }, matched: false)
        }

        let verdict: Verdict = similarity >= 0.85 ? .recognized : similarity >= 0.6 ? .close : .different
        return Result(similarity: similarity, verdict: verdict, words: words, heardText: heard)
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    /// Folds romanisation variants to a canonical skeleton.
    static func normalize(_ word: String) -> String {
        var s = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        s = s.filter(\.isLetter)
        let rules: [(String, String)] = [
            ("zh", "l"), ("ae", "e"), ("ai", "e"), ("ee", "i"), ("oo", "u"), ("oa", "o"), ("aa", "a"),
            ("th", "t"), ("dh", "d"), ("kh", "k"), ("gh", "g"), ("ph", "p"), ("bh", "b"), ("sh", "s"), ("ch", "c"),
            ("w", "v"), ("y", "i"),
        ]
        for (from, to) in rules { s = s.replacingOccurrences(of: from, with: to) }
        // Collapse doubled consonants and vowels (kk -> k, nn -> n).
        var collapsed = ""
        for ch in s where collapsed.last != ch { collapsed.append(ch) }
        return collapsed
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        let distance = levenshtein(Array(a), Array(b))
        return 1 - Double(distance) / Double(max(a.count, b.count))
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// Normalises a word for de-duplicating vocabulary entries.
public enum VocabularyKey {
    public static func make(language: HeritageLanguage, nativeScript: String, transliteration: String) -> String {
        let native = nativeScript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !native.isEmpty { return "\(language.rawValue):n:\(native)" }
        return "\(language.rawValue):t:\(PronunciationScorer.normalize(transliteration))"
    }
}
