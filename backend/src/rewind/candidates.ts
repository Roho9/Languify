import type { ExplainRequest, Explanation } from "../schemas.js";
import { levenshtein, skeleton } from "../text/skeleton.js";

/**
 * Phonetic candidate retrieval for "the word that sounded like X" questions.
 *
 * Runs before the AI. Finds transcript words whose phonetic skeleton matches
 * the learner's rough spelling. Benchmarks showed the model rarely asks for
 * clarification when two words fit (1 of 8 cases), so ambiguity is decided
 * here, deterministically. See docs/benchmarks/ExperimentLog.md, experiment G.
 */
export interface Candidate {
  /** The word or two-word span as the recogniser wrote it. */
  surface: string;
  key: string;
  utterance: number;
  /** Normalised edit distance in [0, 1]; lower is closer. */
  score: number;
}

export const MATCH_THRESHOLD = 0.34;
/** Short partial spellings ("kaa") must match the start of a word almost
 * exactly; one wrong letter in three is too loose. */
export const PREFIX_THRESHOLD = 0.25;
/** Two candidates are "equally plausible" when their scores are this close. */
export const TIE_MARGIN = 0.1;

function score(query: string, word: string): number {
  if (!query || !word) return 1;
  const whole = levenshtein(query, word) / Math.max(query.length, word.length);
  // Short partial spellings ("kaa") are compared with the start of the word.
  const prefix = query.length <= 4 && word.length > query.length ? levenshtein(query, word.slice(0, query.length)) / query.length : 1;
  return Math.min(whole, prefix <= PREFIX_THRESHOLD ? prefix : 1);
}

export function findCandidates(req: Pick<ExplainRequest, "sounds_like" | "transcript">): Candidate[] {
  const raw = req.sounds_like?.trim();
  if (!raw) return [];
  // "thinni or thanni", "madi/mazha": the learner already offered alternatives.
  const queries = raw.split(/\s+or\s+|\s*\/\s*|\s*,\s*/i).map((q) => skeleton(q).replace(/ /g, "")).filter(Boolean);
  const best = new Map<string, Candidate>();
  req.transcript.primary.forEach((segment, utterance) => {
    const words = segment.text.split(/\s+/).filter(Boolean);
    const spans: string[] = [...words];
    for (let i = 0; i + 1 < words.length; i++) spans.push(`${words[i]} ${words[i + 1]}`);
    for (const surface of spans) {
      const key = skeleton(surface).replace(/ /g, "");
      if (key.length < 2) continue;
      const s = Math.min(...queries.map((q) => score(q, key)));
      if (s > MATCH_THRESHOLD) continue;
      // Candidates are distinct when spelled differently. The phonetic key
      // merges t/d/th etc. for tolerant matching, which would conflate
      // genuinely different words (kadai "shop" vs kathai "story").
      const id = surface.toLowerCase().replace(/[^a-z ]/g, "");
      const existing = best.get(id);
      if (!existing || s < existing.score) best.set(id, { surface: surface.replace(/[.,?!]/g, ""), key, utterance, score: s });
    }
  });
  // A two-word span that merely contains a matching single word is the same
  // candidate. Distinct single words are kept even if one spelling contains
  // the other: "paal" (milk) and "paalam" (bridge) are exactly what must be
  // disambiguated.
  const all = [...best.values()].sort((a, b) => a.score - b.score || a.key.length - b.key.length);
  return all.filter((c, i) => !(c.surface.includes(" ") && all.slice(0, i).some((d) => c.key.includes(d.key))));
}

export type Retrieval =
  | { kind: "ambiguous"; candidates: Candidate[] }
  | { kind: "single"; candidate: Candidate }
  | { kind: "none" };

export function classify(candidates: Candidate[]): Retrieval {
  if (candidates.length === 0) return { kind: "none" };
  const [first, second] = candidates;
  if (second && second.score - first.score <= TIE_MARGIN) {
    return { kind: "ambiguous", candidates: candidates.filter((c) => c.score - first.score <= TIE_MARGIN).slice(0, 4) };
  }
  return { kind: "single", candidate: first };
}

/** The clarification returned without calling the AI. */
export function clarificationFor(req: ExplainRequest, candidates: Candidate[]): Explanation {
  const options = candidates.map((c) => c.surface);
  const question = `Which word did you mean: ${options.slice(0, -1).join(", ")} or ${options[options.length - 1]}?`;
  return {
    status: "needs_clarification",
    kind: req.kind,
    spoken_summary: question,
    heard: null,
    items: [],
    suggested_replies: [],
    grammar_note: null,
    clarification: { question, options },
    alternatives: [],
    uncertainty_note: null,
  };
}
