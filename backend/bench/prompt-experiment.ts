// Experiment C: does the tightened explanation prompt (current) reduce
// latency versus the original prompt (git efb50fe), without hurting target
// identification? Calls Ollama directly to capture its token counts and
// timings. Versions alternate case by case (ABAB) so warm-up and thermal drift
// do not favour either. Also measures cold-start (model not loaded) latency.
//
//   npx tsx bench/prompt-experiment.ts [--cases 20] [--model gemma3:27b]
import { execSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import * as v1 from "./prompts/v1.js";
import * as v2 from "../src/ai/prompts.js";
import { Explanation, checkExplanation } from "../src/schemas.js";
import { buildCases, root, toRequest } from "./cases.js";
import { skeleton, targetCer, levenshtein } from "../src/text/skeleton.js";

const args = process.argv.slice(2);
const flag = (n: string) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const model = flag("--model") ?? "gemma3:27b";
const nCases = Number(flag("--cases") ?? "20");
const base = "http://127.0.0.1:11434";

interface Call {
  version: string; caseId: string; kind: string; wallMs: number; hitCap?: boolean;
  promptTokens: number; outputTokens: number; promptEvalMs: number; evalMs: number; loadMs: number;
  valid: boolean; correct?: boolean; status?: string; error?: string;
}

async function chat(system: string, user: string, keepAlive = "30m") {
  const t0 = Date.now();
  const res = await fetch(`${base}/api/chat`, {
    method: "POST",
    // Bounded: an unbounded generation hung the first run of this experiment.
    signal: AbortSignal.timeout(180_000),
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model, stream: false, keep_alive: keepAlive, format: z.toJSONSchema(Explanation), options: { temperature: 0.2, num_predict: 1500 },
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
    }),
  });
  const body = (await res.json()) as any;
  return { wallMs: Date.now() - t0, body };
}

const all = buildCases().filter((c) => c.kind === "sounds_like" || c.kind === "sentence_before");
const cases = [...all.filter((c) => c.kind === "sounds_like").slice(0, Math.ceil(nCases * 0.6)), ...all.filter((c) => c.kind === "sentence_before").slice(0, Math.floor(nCases * 0.4))];

// Cold start: unload the model, then time the first request (3 repetitions).
const cold: { wallMs: number; loadMs: number }[] = [];
for (let i = 0; i < 3; i++) {
  await fetch(`${base}/api/generate`, { method: "POST", body: JSON.stringify({ model, keep_alive: 0 }) });
  await new Promise((r) => setTimeout(r, 3000));
  const req = toRequest(cases[i]);
  const { wallMs, body } = await chat(v2.EXPLAIN_SYSTEM, v2.explainUserTurn(req));
  cold.push({ wallMs, loadMs: (body.load_duration ?? 0) / 1e6 });
  process.stdout.write(`cold ${i + 1}: ${wallMs} ms (load ${(body.load_duration / 1e6).toFixed(0)} ms)\n`);
}

const calls: Call[] = [];
for (const [i, c] of cases.entries()) {
  const order = i % 2 === 0 ? ["v1", "v2"] : ["v2", "v1"];
  for (const version of order) {
    const p = version === "v1" ? v1 : v2;
    const req = toRequest(c);
    let wallMs: number, body: any;
    try {
      ({ wallMs, body } = await chat(p.EXPLAIN_SYSTEM, p.explainUserTurn(req)));
    } catch (e: any) {
      calls.push({ version, caseId: c.id, kind: c.kind, wallMs: 180_000, promptTokens: 0, outputTokens: 0, promptEvalMs: 0, evalMs: 1, loadMs: 0, valid: false, correct: false, error: `client timeout: ${e.name}` });
      continue;
    }
    const call: Call = {
      version, caseId: c.id, kind: c.kind, wallMs,
      promptTokens: body.prompt_eval_count ?? 0, outputTokens: body.eval_count ?? 0,
      promptEvalMs: (body.prompt_eval_duration ?? 0) / 1e6, evalMs: (body.eval_duration ?? 0) / 1e6, loadMs: (body.load_duration ?? 0) / 1e6,
      valid: false, hitCap: body.done_reason === "length",
    };
    try {
      const parsed = Explanation.parse(JSON.parse(body.message.content));
      call.valid = !checkExplanation(parsed);
      call.status = parsed.status;
      if (c.expect.targetSkeleton) {
        const t = c.expect.targetSkeleton.replace(/ /g, "");
        call.correct = parsed.status !== "needs_clarification" && [...parsed.items.map((x) => `${x.transliteration} ${x.native_script}`), parsed.heard?.transliteration ?? ""].some((n) => targetCer(t, skeleton(n)) <= 0.34);
      } else if (c.expect.sentenceSkeleton) {
        const ref = c.expect.sentenceSkeleton.replace(/ /g, "");
        const got = skeleton(parsed.heard?.transliteration || parsed.heard?.native_script || parsed.items.map((x) => x.transliteration).join(" ")).replace(/ /g, "");
        call.correct = got.length > 0 && levenshtein(ref, got) / ref.length <= 0.45;
      }
    } catch (e: any) {
      call.error = String(e.message ?? e).slice(0, 200);
    }
    calls.push(call);
    process.stdout.write(`\r${i + 1}/${cases.length} ${c.id} ${version} ${wallMs} ms out ${call.outputTokens} tok      `);
  }
}
process.stdout.write("\n");

const pct = (xs: number[], p: number) => { const s = [...xs].sort((a, b) => a - b); const r = (p / 100) * (s.length - 1); return s[Math.floor(r)] + (s[Math.ceil(r)] - s[Math.floor(r)]) * (r - Math.floor(r)); };
const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
function summarize(v: string) {
  const cs = calls.filter((c) => c.version === v);
  const judged = cs.filter((c) => c.correct !== undefined);
  return {
    n: cs.length,
    wall_ms: { mean: mean(cs.map((c) => c.wallMs)), p50: pct(cs.map((c) => c.wallMs), 50), p95: pct(cs.map((c) => c.wallMs), 95) },
    output_tokens: { mean: mean(cs.map((c) => c.outputTokens)), p50: pct(cs.map((c) => c.outputTokens), 50) },
    prompt_tokens_mean: mean(cs.map((c) => c.promptTokens)),
    decode_tokens_per_s: mean(cs.map((c) => c.outputTokens / (c.evalMs / 1000))),
    prompt_eval_ms_mean: mean(cs.map((c) => c.promptEvalMs)),
    valid_rate: cs.filter((c) => c.valid).length / cs.length,
    correct_rate: judged.filter((c) => c.correct).length / Math.max(1, judged.length),
    correct: `${judged.filter((c) => c.correct).length}/${judged.length}`,
    hit_token_cap: cs.filter((c) => c.hitCap).length,
    client_timeouts: cs.filter((c) => c.error?.startsWith("client timeout")).length,
  };
}
// Paired bootstrap on per-case wall time difference (v2 - v1).
const pairs = cases.filter((c) => calls.filter((x) => x.caseId === c.id && !x.error).length === 2).map((c) => [calls.find((x) => x.caseId === c.id && x.version === "v1")!.wallMs, calls.find((x) => x.caseId === c.id && x.version === "v2")!.wallMs]);
const diffs = pairs.map(([a, b]) => b - a);
let seed = 13;
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2 ** 31; return seed / 2 ** 31; };
const boots: number[] = [];
for (let i = 0; i < 2000; i++) boots.push(mean(diffs.map(() => diffs[Math.floor(rnd() * diffs.length)])));
boots.sort((a, b) => a - b);
const result = {
  v1: summarize("v1"), v2: summarize("v2"),
  paired_wall_diff_ms: { mean: mean(diffs), ci95: [boots[50], boots[1949]] },
  relative_change: mean(diffs) / mean(pairs.map((p) => p[0])),
  cold_start: { runs: cold, wall_ms_mean: mean(cold.map((c) => c.wallMs)), load_ms_mean: mean(cold.map((c) => c.loadMs)) },
};
const runID = `prompt-${new Date().toISOString().replace(/[:.-]/g, "").slice(0, 15)}Z`;
const meta = {
  benchmark: "prompt-experiment", runID, timestamp: new Date().toISOString(), model,
  gitCommit: execSync("git rev-parse --short HEAD").toString().trim(),
  v1Source: "git efb50fe backend/src/ai/prompts.ts", v2Source: "backend/src/ai/prompts.ts (current)",
  environment: "macOS host, Ollama local, Apple M5 Pro; transcripts are real Apple ta-IN outputs on SYNTHETIC speech",
};
mkdirSync(join(root, "Results/Raw/prompt"), { recursive: true });
writeFileSync(join(root, "Results/Raw/prompt", `${runID}.json`), JSON.stringify({ metadata: meta, result, calls }, null, 1));
console.log(JSON.stringify(result, null, 1));
console.log(`Wrote Results/Raw/prompt/${runID}.json`);
