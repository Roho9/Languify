// Phonetic skeleton matching for romanised Tamil/Malayalam (TypeScript port of
// Benchmarks/scripts/tamil_romanize.py). Used by the phonetic candidate
// retrieval in src/rewind/candidates.ts and by the AI evaluations, so both
// score text the same way as the ASR benchmark.

const VOWELS: Record<string, string> = { "அ": "a", "ஆ": "aa", "இ": "i", "ஈ": "ee", "உ": "u", "ஊ": "oo", "எ": "e", "ஏ": "ae", "ஐ": "ai", "ஒ": "o", "ஓ": "oa", "ஔ": "au" };
const SIGNS: Record<string, string> = { "ா": "aa", "ி": "i", "ீ": "ee", "ு": "u", "ூ": "oo", "ெ": "e", "ே": "ae", "ை": "ai", "ொ": "o", "ோ": "oa", "ௌ": "au" };
const CONS: Record<string, string> = {
  "க": "k", "ங": "ng", "ச": "s", "ஞ": "nj", "ட": "d", "ண": "n", "த": "th", "ந": "n", "ப": "p", "ம": "m",
  "ய": "y", "ர": "r", "ல": "l", "வ": "v", "ழ": "zh", "ள": "l", "ற": "r", "ன": "n", "ஜ": "j", "ஷ": "sh", "ஸ": "s", "ஹ": "h",
};
const VIRAMA = "்";

export function romanize(text: string): string {
  const t = text.normalize("NFC").replaceAll("ற்ற", "ட்ர").replaceAll("ன்ற", "ன்ட்ர");
  const chars = [...t];
  let out = "";
  for (let i = 0; i < chars.length; i++) {
    const c = chars[i], n = chars[i + 1] ?? "";
    if (CONS[c]) {
      if (n === VIRAMA) { out += CONS[c]; i++; }
      else if (SIGNS[n]) { out += CONS[c] + SIGNS[n]; i++; }
      else out += CONS[c] + "a";
    } else if (VOWELS[c]) out += VOWELS[c];
    else if (c === "ஃ") out += "h";
    else out += c;
  }
  return out;
}

const MULTI: [string, string][] = [
  ["zh", "l"], ["th", "t"], ["dh", "t"], ["ch", "s"], ["sh", "s"], ["kh", "k"], ["gh", "k"], ["ph", "p"], ["bh", "p"], ["ng", "n"], ["nj", "n"], ["ny", "n"],
  ["aa", "a"], ["ee", "i"], ["ii", "i"], ["oo", "u"], ["uu", "u"], ["ae", "e"], ["oa", "o"], ["ai", "e"],
];
const SINGLE: Record<string, string> = { g: "k", d: "t", b: "p", j: "s", c: "s", z: "s", f: "p", w: "v", y: "i", q: "k", x: "k" };

export function skeleton(text: string): string {
  let s = text.toLowerCase();
  if (/[஀-௿]/.test(s)) s = romanize(s);
  s = s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z\s]/g, " ");
  for (const [a, b] of MULTI) s = s.replaceAll(a, b);
  s = [...s].map((c) => SINGLE[c] ?? c).join("");
  s = s.replace(/([a-z])\1+/g, "$1");
  return s.replace(/\s+/g, " ").trim();
}

export function levenshtein(a: string, b: string): number {
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[b.length];
}

/** Best CER of `target` against 1 to 3 consecutive words of `text`, or their edges. */
export function targetCer(target: string, text: string): number {
  const tokens = text.split(" ").filter(Boolean);
  const spans: string[] = [];
  for (const k of [1, 2, 3]) for (let i = 0; i + k <= tokens.length; i++) spans.push(tokens.slice(i, i + k).join(""));
  const cands = [...spans, ...spans.filter((s) => s.length > target.length).flatMap((s) => [s.slice(-target.length), s.slice(0, target.length)])];
  return Math.min(1, ...cands.map((s) => levenshtein(target, s) / Math.max(1, target.length)));
}
