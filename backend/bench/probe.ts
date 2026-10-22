// Diagnostic: runs specific evaluation cases against Ollama and prints token
// counts, stop reason and trailing whitespace, to explain slow or runaway calls.
//   npx tsx bench/probe.ts <case-id>... [--prompt v1|v2] [--num-predict N]
import { z } from "zod";
import * as v1 from "./prompts/v1.js";
import * as v2 from "../src/ai/prompts.js";
import { Explanation } from "../src/schemas.js";
import { buildCases, toRequest } from "./cases.js";

const args = process.argv.slice(2);
const flag = (n: string, d: string) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const p = flag("--prompt", "v2") === "v1" ? v1 : v2;
const numPredict = Number(flag("--num-predict", "1500"));
const ids = args.filter((a, i) => !a.startsWith("--") && !args[i - 1]?.startsWith("--"));
for (const c of buildCases().filter((x) => ids.includes(x.id))) {
  const t0 = Date.now();
  try {
    const res = await fetch("http://127.0.0.1:11434/api/chat", {
      method: "POST", signal: AbortSignal.timeout(240_000),
      body: JSON.stringify({ model: "gemma3:27b", stream: false, format: z.toJSONSchema(Explanation), options: { temperature: 0.2, num_predict: numPredict }, messages: [{ role: "system", content: p.EXPLAIN_SYSTEM }, { role: "user", content: p.explainUserTurn(toRequest(c)) }] }),
    });
    const b: any = await res.json();
    const content: string = b.message.content;
    console.log(`${c.id} ${Date.now() - t0} ms | prompt tok ${b.prompt_eval_count} | out tok ${b.eval_count} | done ${b.done_reason} | trailing ws ${content.length - content.trimEnd().length} | json chars ${content.trim().length}`);
  } catch (e: any) {
    console.log(`${c.id} ${Date.now() - t0} ms | ${e.name}`);
  }
}
