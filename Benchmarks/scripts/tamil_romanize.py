"""Deterministic Tamil-script romanisation plus a phonetic "skeleton" used to
compare references with Apple's romanised Tamil transcripts.

Why a skeleton: Apple's ta-IN model writes Tamil in Latin letters with its own
spelling habits (poagiraen, vaenum, ezhunthirukkanum). Tamil also voices stops
between vowels (k/g, t/d, p/b, c/s). Comparing raw strings would count those
spelling conventions as errors. Both reference and hypothesis are reduced to
the same skeleton: voicing merged, aspirate digraphs merged, vowel length
merged, doubled letters collapsed. This can hide genuine length errors, which
is documented in BenchmarkMethodology.md.
"""
import re
import unicodedata

VOWELS = {"அ": "a", "ஆ": "aa", "இ": "i", "ஈ": "ee", "உ": "u", "ஊ": "oo", "எ": "e", "ஏ": "ae", "ஐ": "ai", "ஒ": "o", "ஓ": "oa", "ஔ": "au"}
SIGNS = {"ா": "aa", "ி": "i", "ீ": "ee", "ு": "u", "ூ": "oo", "ெ": "e", "ே": "ae", "ை": "ai", "ொ": "o", "ோ": "oa", "ௌ": "au"}
CONSONANTS = {
    "க": "k", "ங": "ng", "ச": "s", "ஞ": "nj", "ட": "d", "ண": "n", "த": "th", "ந": "n", "ப": "p", "ம": "m",
    "ய": "y", "ர": "r", "ல": "l", "வ": "v", "ழ": "zh", "ள": "l", "ற": "r", "ன": "n",
    "ஜ": "j", "ஷ": "sh", "ஸ": "s", "ஹ": "h",
}
VIRAMA = "்"
AYTHAM = "ஃ"


def romanize(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    # Common spoken clusters.
    text = text.replace("ற்ற", "ட்ர").replace("ன்ற", "ன்ட்ர")
    out = []
    chars = list(text)
    i = 0
    while i < len(chars):
        c = chars[i]
        nxt = chars[i + 1] if i + 1 < len(chars) else ""
        if c in CONSONANTS:
            base = CONSONANTS[c]
            if nxt == VIRAMA:
                out.append(base)
                i += 2
                continue
            if nxt in SIGNS:
                out.append(base + SIGNS[nxt])
                i += 2
                continue
            out.append(base + "a")
        elif c in VOWELS:
            out.append(VOWELS[c])
        elif c == AYTHAM:
            out.append("h")
        else:
            out.append(c)
        i += 1
    return "".join(out)


MULTI = [
    ("zh", "l"), ("th", "t"), ("dh", "t"), ("ch", "s"), ("sh", "s"), ("kh", "k"), ("gh", "k"),
    ("ph", "p"), ("bh", "p"), ("ng", "n"), ("nj", "n"), ("ny", "n"),
    ("aa", "a"), ("ee", "i"), ("ii", "i"), ("oo", "u"), ("uu", "u"), ("ae", "e"), ("oa", "o"), ("ai", "e"),
]
SINGLE = str.maketrans({"g": "k", "d": "t", "b": "p", "j": "s", "c": "s", "z": "s", "f": "p", "w": "v", "y": "i", "q": "k", "x": "k"})


def skeleton(text: str) -> str:
    """Phonetic key used for both reference and hypothesis."""
    s = text.lower()
    if any("஀" <= ch <= "௿" for ch in s):
        s = romanize(s)
    s = re.sub(r"[^a-z\s]", " ", s)
    for a, b in MULTI:
        s = s.replace(a, b)
    s = s.translate(SINGLE)
    s = re.sub(r"([a-z])\1+", r"\1", s)
    return re.sub(r"\s+", " ", s).strip()


def latin_words(text: str):
    """English words embedded in a code-switched reference."""
    return [w.lower() for w in re.findall(r"[A-Za-z]+", text)]
