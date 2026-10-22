import type { LanguageAI } from "../ai/provider.js";
import type { ExplainInput, ExplainRequest, Explanation } from "../schemas.js";
import { classify, clarificationFor, findCandidates, type Retrieval } from "./candidates.js";

export type ExplainPath = "model" | "model_with_phonetic_hint" | "phonetic_clarification";

/**
 * Deterministic phonetic retrieval for "sounded like" questions. Returns null
 * when it does not apply (disabled, no spelling given, or the learner is
 * already answering a clarification).
 */
export function retrieve(req: ExplainRequest, enabled = true): Retrieval | null {
  if (!enabled || !req.sounds_like || req.clarification) return null;
  return classify(findCandidates(req));
}

/**
 * Live Rewind explanation with retrieval in front of the model. Ambiguous
 * questions get an immediate clarification with no model call; a single
 * match is passed to the model as a hint; everything else goes to the model
 * unchanged. See docs/benchmarks/ExperimentLog.md, experiment G.
 */
export async function explainWithRetrieval(
  ai: LanguageAI,
  req: ExplainRequest,
  retrieval: Retrieval | null,
): Promise<{ explanation: Explanation; path: ExplainPath }> {
  if (retrieval?.kind === "ambiguous") {
    return { explanation: clarificationFor(req, retrieval.candidates), path: "phonetic_clarification" };
  }
  if (retrieval?.kind === "single") {
    const hinted: ExplainInput = { ...req, phonetic_match: { surface: retrieval.candidate.surface, utterance: retrieval.candidate.utterance } };
    return { explanation: await ai.explain(hinted), path: "model_with_phonetic_hint" };
  }
  return { explanation: await ai.explain(req), path: "model" };
}
