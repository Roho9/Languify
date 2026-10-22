import { describe, expect, it } from "vitest";
import { classify, findCandidates } from "../src/rewind/candidates.js";
import { explainWithRetrieval, retrieve } from "../src/rewind/pipeline.js";
import type { ExplainRequest } from "../src/schemas.js";

const req = (soundsLike: string | null, ...utterances: string[]): ExplainRequest => ({
  language: "ta", question: "What did that word mean?", kind: "word", sounds_like: soundsLike, detail_level: "concise",
  transcript: { language_code: "ta", primary: utterances.map((text, i) => ({ text, start: i, end: i + 1, confidence: 0.9, alternatives: [] })), english: [], window_seconds: 60 },
  learner: { comprehension: 4, speaking: 2, reading: 1, recent_words: [] },
});

describe("phonetic candidate retrieval", () => {
  it("finds the word from a rough learner spelling", () => {
    const r = classify(findCandidates(req("sapadu", "innaikku saappaadu romba nallaa irukku")));
    expect(r).toMatchObject({ kind: "single", candidate: { surface: "saappaadu" } });
  });

  it("flags two different words that both fit a partial spelling", () => {
    const r = classify(findCandidates(req("kaa", "amma kaaram jaasthi poattutaanga", "nethu kaalam maarippoachchu")));
    expect(r.kind).toBe("ambiguous");
    expect(r.kind === "ambiguous" && r.candidates.map((c) => c.surface)).toEqual(expect.arrayContaining(["kaaram", "kaalam"]));
  });

  it("keeps words distinct even when one spelling contains the other", () => {
    const r = classify(findCandidates(req("paa", "paal vaangittu vaa", "antha paalam romba pazhasu")));
    expect(r.kind === "ambiguous" && r.candidates.map((c) => c.surface)).toEqual(expect.arrayContaining(["paal", "paalam"]));
  });

  it("separates words the phonetic key would merge (kadai vs kathai)", () => {
    expect(classify(findCandidates(req("kadha", "kadai moodiyaachu", "antha kathai enakku pidikkala"))).kind).toBe("ambiguous");
  });

  it("treats the same word in two utterances as one candidate", () => {
    expect(classify(findCandidates(req("veedu", "avanga veedu pakkaththula", "intha veedu romba periyathu"))).kind).toBe("single");
  });

  it("honours learner-supplied alternatives", () => {
    expect(classify(findCandidates(req("thinni or thanni", "thanni kudu", "thinni mudichchiyaa"))).kind).toBe("ambiguous");
  });

  it("does not match a short spelling to a word with a different first sound", () => {
    expect(findCandidates(req("pal", "kalyaanaththukku ellaarum varuvaanga"))).toEqual([]);
  });

  it("returns nothing when the word is absent", () => {
    expect(classify(findCandidates(req("kuzhappam", "naan naalaikku chennaikku poagiraen"))).kind).toBe("none");
  });

  it("does not apply without a spelling or during a clarification follow-up", () => {
    expect(retrieve(req(null, "anything"))).toBeNull();
    expect(retrieve({ ...req("kaa", "kaaram", "kaalam"), clarification: { question: "Which?", chosen_option: "kaaram" } })).toBeNull();
  });
});

describe("explain pipeline", () => {
  const seen: unknown[] = [];
  const ai = {
    explain: async (r: any) => { seen.push(r); return { status: "answered", kind: "word", spoken_summary: "ok", heard: null, items: [], suggested_replies: [], grammar_note: "x", clarification: null, alternatives: [], uncertainty_note: null } as any; },
    tutorTurn: async () => { throw new Error(); }, suggestions: async () => { throw new Error(); }, lesson: async () => { throw new Error(); },
  };

  it("answers ambiguity without calling the model", async () => {
    seen.length = 0;
    const r = req("kaa", "amma kaaram jaasthi", "nethu kaalam maarippoachchu");
    const out = await explainWithRetrieval(ai, r, retrieve(r));
    expect(out.path).toBe("phonetic_clarification");
    expect(out.explanation.clarification?.options.length).toBe(2);
    expect(seen).toHaveLength(0);
  });

  it("passes a single match to the model as a hint", async () => {
    seen.length = 0;
    const r = req("sapadu", "innaikku saappaadu romba nallaa irukku");
    const out = await explainWithRetrieval(ai, r, retrieve(r));
    expect(out.path).toBe("model_with_phonetic_hint");
    expect((seen[0] as any).phonetic_match).toEqual({ surface: "saappaadu", utterance: 0 });
  });
});
