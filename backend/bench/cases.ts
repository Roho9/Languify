// Labelled evaluation cases shared by context-eval.ts and prompt-experiment.ts.
// Transcripts are REAL Apple ta-IN outputs on the SYNTHETIC Tamil pilot clips.
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExplainRequest } from "../src/schemas.js";
import { skeleton } from "../src/text/skeleton.js";

const here = dirname(fileURLToPath(import.meta.url));
export const root = join(here, "../..");

export type Kind = "sounds_like" | "sentence_before" | "ambiguous" | "unanswerable" | "respond";
export interface Case {
  id: string;
  kind: Kind;
  question: string;
  qkind: ExplainRequest["kind"];
  soundsLike?: string;
  segments: { text: string; confidence: number | null }[];
  expect: {
    targetSkeleton?: string;
    targetMeaning?: string;
    sentenceSkeleton?: string;
    clarification?: boolean;
    abstain?: boolean;
  };
}

// ---- Inputs

const annotations = JSON.parse(readFileSync(join(root, "BenchmarkData/Annotations/tamil_pilot_v1.json"), "utf8"));
const sentences: Record<string, any> = Object.fromEntries(annotations.sentences.map((s: any) => [s.id, s]));
const asrRuns = readdirSync(join(root, "Results/Raw/asr")).filter((f) => f.endsWith(".json")).sort();
const fullRun = asrRuns.map((f) => JSON.parse(readFileSync(join(root, "Results/Raw/asr", f), "utf8"))).find((r) => r.results.length >= 500);
if (!fullRun) throw new Error("Run the full ASR benchmark first");
const heard: Record<string, { text: string; confidence: number | null }> = {};
for (const r of fullRun.results) {
  if (r.condition === "clean" && r.rate === "normal") {
    const ta = r.hypotheses.find((h: any) => h.locale.startsWith("ta"));
    heard[r.sentenceID] = { text: ta?.text ?? "", confidence: ta?.meanConfidence ?? null };
  }
}

/** A learner's rough spelling: deterministic perturbations of the target. */
function roughSpelling(translit: string, i: number): string {
  const rules: [RegExp, string][] = [
    [/aa/g, "a"], [/ee/g, "i"], [/oo/g, "u"], [/th/g, "t"], [/dh/g, "d"], [/zh/g, "l"], [/(.)\1/g, "$1"], [/k/g, "g"],
  ];
  let s = translit.toLowerCase();
  for (let r = 0; r < rules.length; r++) if ((i + r) % 2 === 0) s = s.replace(rules[r][0], rules[r][1]);
  return s;
}

export function buildCases(): Case[] {
  const ids = Object.keys(heard).filter((id) => heard[id].text);
  const cases: Case[] = [];
  // 1. Sounds-like lookups: three-sentence conversation, target in the middle or last.
  ids.forEach((id, i) => {
    const prev = ids[(i + 11) % ids.length];
    const next = ids[(i + 23) % ids.length];
    const order = i % 2 === 0 ? [prev, id] : [prev, id, next];
    const t = sentences[id].target;
    const sl = roughSpelling(t.transliteration, i);
    cases.push({
      id: `sl-${id}`, kind: "sounds_like", qkind: "word",
      question: `What does the word that sounded like "${sl}" mean?`, soundsLike: sl,
      segments: order.map((x) => heard[x]),
      expect: { targetSkeleton: skeleton(t.native), targetMeaning: t.meaning },
    });
  });
  // 2. "The sentence before that": target is the second of three.
  ids.slice(0, 16).forEach((id, i) => {
    const a = ids[(i + 5) % ids.length], c = ids[(i + 9) % ids.length];
    cases.push({
      id: `sb-${id}`, kind: "sentence_before", qkind: "sentence",
      question: "What did the sentence before that one mean?",
      segments: [heard[a], heard[id], heard[c]],
      expect: { sentenceSkeleton: skeleton(sentences[id].text) },
    });
  });
  // 3. Ambiguous: two similar-sounding words, vague spelling matching both.
  const ambiguous: [string, string, string][] = [
    ["amma kaaram jaasthi poattutaanga", "nethu kaalam maarippoachchu", "kaa"],
    ["paal vaangittu vaa", "antha paalam romba pazhasu", "paa"],
    ["avan romba vaali", "intha vaazhai pazham nallaa irukku", "vaa"],
    ["kadai moodiyaachu", "antha kathai enakku pidikkala", "kadha"],
    ["avanga veedu pakkaththula", "intha veedu romba periyathu", "veedu"],
    ["thanni kudu", "thinni mudichchiyaa", "thinni or thanni"],
    ["pasikkuthu", "pasanga ellaarum vanthaanga", "pasa"],
    ["avan kurumbu pannuraan", "kuruvi kooduvittu parandhuchu", "kuru"],
  ];
  ambiguous.forEach(([a, b, sl], i) => cases.push({
    id: `amb-${i + 1}`, kind: "ambiguous", qkind: "word",
    question: `What did that word mean, the one that sounded like "${sl}"?`, soundsLike: sl,
    segments: [{ text: a, confidence: 0.9 }, { text: b, confidence: 0.9 }],
    expect: { clarification: true },
  }));
  // 4. Unanswerable: the asked-about word is not in the transcript.
  ids.slice(0, 8).forEach((id, i) => cases.push({
    id: `un-${id}`, kind: "unanswerable", qkind: "word",
    question: `What does the word that sounded like "${["kuzhappam", "samaiyal", "thiruvizha", "kovam", "parisu", "nilaa", "kanavu", "vilakku"][i]}" mean?`,
    soundsLike: ["kuzhappam", "samaiyal", "thiruvizha", "kovam", "parisu", "nilaa", "kanavu", "vilakku"][i],
    segments: [heard[id]],
    expect: { abstain: true },
  }));
  // 5. How to respond.
  ids.slice(20, 30).forEach((id) => cases.push({
    id: `re-${id}`, kind: "respond", qkind: "respond", question: "How should I respond in Tamil?",
    segments: [heard[id]], expect: {},
  }));
  return cases;
}


export function toRequest(c: Case): ExplainRequest {
  return {
    language: "ta", question: c.question, kind: c.qkind, sounds_like: c.soundsLike ?? null, detail_level: "concise",
    transcript: {
      language_code: "ta",
      primary: c.segments.map((s, k) => ({ text: s.text, start: k * 4, end: k * 4 + 3, confidence: s.confidence, alternatives: [] })),
      english: [], window_seconds: 60,
    },
    learner: { comprehension: 4, speaking: 2, reading: 1, recent_words: [] },
  };
}
