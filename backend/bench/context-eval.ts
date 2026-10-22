// Contextual retrieval evaluation: does the AI identify the word or sentence
// the learner meant, ask when it should, and refuse to invent answers?
//
// Inputs are REAL on-device recogniser outputs (Apple ta-IN on the synthetic
// Tamil pilot clips), arranged into labelled conversations. Automatic checks
// cover target identification, localisation, clarification and abstention.
// Explanation QUALITY is not auto-scored: a review sheet is exported for
// bilingual reviewers (docs/benchmarks/TranslationReviewRubric.md).
//
//   npx tsx bench/context-eval.ts [--provider ollama|claude] [--limit N] [--retrieval on|off] [--kinds sounds_like,ambiguous,...]
import { mkdirSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createLanguageAI } from "../src/ai/factory.js";
import { loadConfig } from "../src/config.js";
import { checkExplanation, type Explanation } from "../src/schemas.js";
import { explainWithRetrieval, retrieve } from "../src/rewind/pipeline.js";
import { skeleton, levenshtein, targetCer } from "../src/text/skeleton.js";
import { buildCases, root, toRequest, type Case, type Kind } from "./cases.js";

const here = dirname(fileURLToPath(import.meta.url));

// ---- Run

const args = process.argv.slice(2);
const flag = (name: string) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const config = loadConfig({ LANGUIFY_TOKEN_SECRET: "bench-only-not-a-real-secret-value-xx", ...process.env, ...(flag("--provider") ? { AI_PROVIDER: flag("--provider") } : {}) });
const promptVersion = execSync("git log -1 --format=%h -- src/ai/prompts.ts", { cwd: join(here, "..") }).toString().trim() || "working-tree";
const ai = createLanguageAI(config);
const limit = Number(flag("--limit") ?? "0");
const retrievalOn = (flag("--retrieval") ?? "on") === "on";
const kinds = flag("--kinds")?.split(",");
let cases = buildCases().filter((c) => !kinds || kinds.includes(c.kind));
if (limit) {
  // Keep every kind represented when limiting.
  const byKind = new Map<Kind, Case[]>();
  for (const c of cases) byKind.set(c.kind, [...(byKind.get(c.kind) ?? []), c]);
  cases = [...byKind.values()].flatMap((cs) => cs.slice(0, Math.max(1, Math.round((limit * cs.length) / cases.length))));
}

interface Outcome {
  id: string; kind: Kind; question: string; latencyMs: number; error?: string; path?: string;
  status?: string; schemaValid: boolean; targetIdentified?: boolean; sentenceLocalised?: boolean;
  clarified?: boolean; abstained?: boolean; confidentWrong?: boolean; nativeScriptValid?: boolean;
  replies?: number; output?: Explanation;
}

const outcomes: Outcome[] = [];
const started = Date.now();
for (const [i, c] of cases.entries()) {
  const request = toRequest(c);
  const t0 = Date.now();
  let out: Explanation | undefined;
  let error: string | undefined;
  let path: string | undefined;
  try {
    const result = await explainWithRetrieval(ai, request, retrieve(request, retrievalOn));
    out = result.explanation;
    path = result.path;
  } catch (e: any) {
    error = `${e.kind ?? "error"}: ${e.message}`;
  }
  const latencyMs = Date.now() - t0;
  const o: Outcome = { id: c.id, kind: c.kind, question: c.question, latencyMs, error, path, status: out?.status, schemaValid: !!out && !checkExplanation(out), output: out };
  if (out) {
    const tamilScript = /[஀-௿]/;
    const natives = [...out.items.map((x) => x.native_script), out.heard?.native_script ?? "", ...out.suggested_replies.map((r) => r.native_script)].filter(Boolean);
    o.nativeScriptValid = natives.length === 0 ? undefined : natives.every((n) => tamilScript.test(n));
    if (c.expect.targetSkeleton) {
      const t = c.expect.targetSkeleton.replace(/ /g, "");
      const named = [...out.items.map((x) => x.transliteration + " " + x.native_script), out.heard?.transliteration ?? ""];
      o.targetIdentified = out.status !== "needs_clarification" && named.some((n) => targetCer(t, skeleton(n)) <= 0.34);
    }
    if (c.expect.sentenceSkeleton) {
      const ref = c.expect.sentenceSkeleton.replace(/ /g, "");
      const got = skeleton(out.heard?.transliteration || out.heard?.native_script || out.items.map((x) => x.transliteration).join(" ")).replace(/ /g, "");
      o.sentenceLocalised = got.length > 0 && levenshtein(ref, got) / ref.length <= 0.45;
    }
    o.clarified = out.status === "needs_clarification";
    o.abstained = out.status === "no_relevant_speech" || out.status === "uncertain" || out.status === "needs_clarification";
    if (c.expect.abstain) o.confidentWrong = out.status === "answered" && out.items.length > 0;
    o.replies = out.suggested_replies.length;
  }
  outcomes.push(o);
  process.stdout.write(`\r${i + 1}/${cases.length} ${c.id} ${o.status ?? o.error} ${latencyMs}ms        `);
}
process.stdout.write("\n");

// ---- Aggregate

const wilson = (k: number, n: number) => {
  if (!n) return [NaN, NaN];
  const z = 1.96, p = k / n, d = 1 + (z * z) / n, c = (p + (z * z) / (2 * n)) / d;
  const h = (z * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n))) / d;
  return [Math.max(0, c - h), Math.min(1, c + h)];
};
const pct = (xs: number[], p: number) => { const s = [...xs].sort((a, b) => a - b); const r = (p / 100) * (s.length - 1); const lo = Math.floor(r), hi = Math.ceil(r); return s[lo] + (s[hi] - s[lo]) * (r - lo); };
const rate = (xs: Outcome[], f: (o: Outcome) => boolean | undefined) => {
  const valid = xs.filter((o) => f(o) !== undefined);
  const k = valid.filter((o) => f(o)).length;
  return { k, n: valid.length, rate: valid.length ? k / valid.length : NaN, ci95: wilson(k, valid.length) };
};
const of = (k: Kind) => outcomes.filter((o) => o.kind === k);
const summary = {
  n_cases: outcomes.length,
  errors: outcomes.filter((o) => o.error).length,
  schema_and_semantic_valid: rate(outcomes, (o) => o.schemaValid),
  native_script_valid: rate(outcomes, (o) => o.nativeScriptValid),
  target_identification: rate(of("sounds_like"), (o) => o.targetIdentified),
  sentence_localisation: rate(of("sentence_before"), (o) => o.sentenceLocalised),
  clarification_when_ambiguous: rate(of("ambiguous"), (o) => o.clarified),
  abstention_when_unanswerable: rate(of("unanswerable"), (o) => o.abstained),
  confident_wrong_when_unanswerable: rate(of("unanswerable"), (o) => o.confidentWrong),
  unnecessary_clarification_on_clear_lookups: rate(of("sounds_like"), (o) => o.clarified),
  respond_has_replies: rate(of("respond"), (o) => (o.replies ?? 0) > 0),
  latency_ms: Object.fromEntries((["sounds_like", "sentence_before", "ambiguous", "unanswerable", "respond"] as Kind[]).map((k) => {
    const l = of(k).map((o) => o.latencyMs);
    return [k, { n: l.length, p50: pct(l, 50), p90: pct(l, 90), p95: pct(l, 95), max: Math.max(...l) }];
  })),
  latency_all_ms: (() => { const l = outcomes.map((o) => o.latencyMs); return { p50: pct(l, 50), p90: pct(l, 90), p95: pct(l, 95), mean: l.reduce((a, b) => a + b, 0) / l.length }; })(),
};

const runID = `context-${config.AI_PROVIDER}-${promptVersion}-retrieval_${retrievalOn ? "on" : "off"}-${new Date().toISOString().replace(/[:.-]/g, "").slice(0, 15)}Z`;
const meta = {
  benchmark: "context", runID, timestamp: new Date().toISOString(),
  gitCommit: execSync("git rev-parse --short HEAD").toString().trim(),
  retrieval: retrievalOn, kinds: kinds ?? "all", provider: config.AI_PROVIDER, model: config.AI_PROVIDER === "ollama" ? config.OLLAMA_MODEL : config.ANTHROPIC_MODEL, promptVersion,
  environment: "macOS host; transcripts are real Apple ta-IN outputs on SYNTHETIC speech; ambiguous/unanswerable cases hand-written",
  wallSeconds: (Date.now() - started) / 1000,
};
mkdirSync(join(root, "Results/Raw/context"), { recursive: true });
writeFileSync(join(root, "Results/Raw/context", `${runID}.json`), JSON.stringify({ metadata: meta, summary, outcomes }, null, 1));

// Review sheet for bilingual reviewers (quality is not auto-scored).
const csvEscape = (s: unknown) => `"${String(s ?? "").replace(/"/g, '""')}"`;
const header = ["case_id", "kind", "question", "transcript", "expected_meaning", "status", "summary", "word_native", "word_translit", "meaning", "contextual_meaning", "replies", "semantic_accuracy_0_2", "contextual_correctness_0_2", "fluency_0_2", "cultural_appropriateness_0_2", "unsupported_claims_y_n", "usefulness_0_2", "reviewer", "notes"];
const lines = [header.join(",")];
for (const o of outcomes) {
  const c = cases.find((x) => x.id === o.id)!;
  const item = o.output?.items[0];
  lines.push([o.id, o.kind, o.question, c.segments.map((s) => s.text).join(" | "), c.expect.targetMeaning ?? "", o.status ?? o.error, o.output?.spoken_summary, item?.native_script, item?.transliteration, item?.english_meaning, item?.contextual_meaning, o.output?.suggested_replies.map((r) => `${r.native_script} (${r.english})`).join("; "), "", "", "", "", "", "", "", ""].map(csvEscape).join(","));
}
mkdirSync(join(root, "Results/Reviews"), { recursive: true });
writeFileSync(join(root, "Results/Reviews", `${runID}.csv`), lines.join("\n"));

console.log(JSON.stringify(summary, null, 1));
console.log(`Wrote Results/Raw/context/${runID}.json and Results/Reviews/${runID}.csv`);
