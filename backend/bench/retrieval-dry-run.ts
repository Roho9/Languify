// Deterministic check of phonetic retrieval on every labelled case, no model:
// how often it would clarify, hint the right word, hint a wrong word, or pass.
//   npx tsx bench/retrieval-dry-run.ts
import { retrieve } from "../src/rewind/pipeline.js";
import { skeleton, targetCer } from "../src/text/skeleton.js";
import { buildCases, toRequest } from "./cases.js";

const tally: Record<string, Record<string, number>> = {};
const notes: string[] = [];
for (const c of buildCases()) {
  const r = retrieve(toRequest(c));
  let outcome = r?.kind ?? "not_applicable";
  if (r?.kind === "single" && c.expect.targetSkeleton) {
    const ok = targetCer(c.expect.targetSkeleton.replace(/ /g, ""), skeleton(r.candidate.surface)) <= 0.34;
    outcome = ok ? "single_correct" : "single_wrong";
    if (!ok) notes.push(`${c.id}: sounds like "${c.soundsLike}" -> hinted "${r.candidate.surface}" (score ${r.candidate.score.toFixed(2)})`);
  }
  if (r?.kind === "ambiguous") notes.push(`${c.id}: sounds like "${c.soundsLike}" -> ask about ${r.candidates.map((x) => `${x.surface} (${x.score.toFixed(2)})`).join(", ")}`);
  if (r?.kind === "none" && c.kind === "sounds_like") notes.push(`${c.id}: sounds like "${c.soundsLike}" -> no match`);
  (tally[c.kind] ??= {})[outcome] = ((tally[c.kind] ??= {})[outcome] ?? 0) + 1;
}
console.log(JSON.stringify(tally, null, 1));
console.log(notes.join("\n"));
