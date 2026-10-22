// Staged load test for POST /v1/rewind/explain.
//
//   Mock AI (infrastructure capacity, AI replaced by a labelled mock):
//     npx tsx bench/load-test.ts --ai mock --mock-latency 300 --stages 1,10,25,50,100,200 --seconds 10
//   Real local model (small, bounded, free):
//     npx tsx bench/load-test.ts --ai real --stages 1,2,4,8 --requests-per-worker 2 [--limit 1 --queue 2 --wait 20000]
//
// Each virtual user has its own token (as separate phones would). Results go
// to Results/Raw/load/<runID>.json.
import { spawn } from "node:child_process";
import { execSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { TokenService } from "../src/auth/tokens.js";
import { buildCases, root, toRequest } from "./cases.js";

const args = process.argv.slice(2);
const flag = (n: string, d?: string) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const aiMode = flag("--ai", "mock")!;
const stages = flag("--stages", "1,10,25,50,100")!.split(",").map(Number);
const seconds = Number(flag("--seconds", "10"));
const perWorker = Number(flag("--requests-per-worker", "0"));
const clientTimeoutMs = Number(flag("--client-timeout", "60000"));
const secret = "load-test-secret-load-test-secret-123";

const server = spawn("npx", ["tsx", "bench/load-server.ts"], {
  cwd: join(root, "backend"),
  env: {
    ...process.env, LANGUIFY_TOKEN_SECRET: secret, LOAD_AI: aiMode, MOCK_LATENCY_MS: flag("--mock-latency", "300"),
    LIMIT_CONCURRENCY: flag("--limit", "0"), LIMIT_QUEUE: flag("--queue", "8"), LIMIT_WAIT_MS: flag("--wait", "20000"),
  },
  stdio: ["ignore", "pipe", "inherit"],
});
const stats: any[] = [];
const port: number = await new Promise((resolve) => {
  let buf = "";
  server.stdout.on("data", (d) => {
    buf += d.toString();
    let nl;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl);
      buf = buf.slice(nl + 1);
      if (line.startsWith("READY ")) resolve(Number(line.slice(6)));
      else if (line.startsWith("{")) stats.push(JSON.parse(line));
    }
  });
});
const url = `http://127.0.0.1:${port}/v1/rewind/explain`;
const tokens = new TokenService(secret);
const requests = buildCases().filter((c) => c.kind === "sounds_like").map((c) => JSON.stringify(toRequest(c)));

interface Sample { stage: number; start: number; ms: number; status: number; error?: string }
const samples: Sample[] = [];

async function worker(stage: number, id: number, until: number) {
  const { token } = await tokens.issue(`install:00000000-0000-4000-8000-${String(stage * 1000 + id).padStart(12, "0")}`);
  let n = 0;
  while ((perWorker ? n < perWorker : Date.now() < until)) {
    const body = requests[(id + n) % requests.length];
    const start = Date.now();
    try {
      const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${token}` }, body, signal: AbortSignal.timeout(clientTimeoutMs) });
      await res.arrayBuffer();
      samples.push({ stage, start, ms: Date.now() - start, status: res.status });
    } catch (e: any) {
      samples.push({ stage, start, ms: Date.now() - start, status: 0, error: e.name === "TimeoutError" ? "client_timeout" : e.name });
    }
    n++;
  }
}

const stageWindows: { stage: number; start: number; end: number }[] = [];
for (const c of stages) {
  const start = Date.now();
  await Promise.all(Array.from({ length: c }, (_, i) => worker(c, i, start + seconds * 1000)));
  stageWindows.push({ stage: c, start, end: Date.now() });
  process.stdout.write(`stage ${c}: ${samples.filter((s) => s.stage === c).length} requests\n`);
  await new Promise((r) => setTimeout(r, 1000));
}
server.kill();

const pct = (xs: number[], p: number) => { if (!xs.length) return NaN; const s = [...xs].sort((a, b) => a - b); const r = (p / 100) * (s.length - 1); return s[Math.floor(r)] + (s[Math.ceil(r)] - s[Math.floor(r)]) * (r - Math.floor(r)); };
const summary = stageWindows.map(({ stage, start, end }) => {
  const ss = samples.filter((s) => s.stage === stage);
  const ok = ss.filter((s) => s.status === 200);
  const dur = (end - start) / 1000;
  const st = stats.filter((s) => s.t >= start && s.t <= end);
  const okMs = ok.map((s) => s.ms);
  return {
    concurrency: stage, requests: ss.length, duration_s: dur,
    throughput_rps: ss.length / dur, goodput_rps: ok.length / dur,
    success_rate: ok.length / Math.max(1, ss.length),
    latency_ok_ms: { p50: pct(okMs, 50), p95: pct(okMs, 95), p99: ss.length >= 100 ? pct(okMs, 99) : null, max: okMs.length ? Math.max(...okMs) : null },
    failed_request_ms_p50: pct(ss.filter((s) => s.status !== 200).map((s) => s.ms), 50),
    statuses: ss.reduce((m: Record<string, number>, s) => { const k = s.error ?? String(s.status); m[k] = (m[k] ?? 0) + 1; return m; }, {}),
    server_cpu_percent_mean: st.length ? st.reduce((a, s) => a + s.cpuPercent, 0) / st.length : null,
    server_rss_mb_max: st.length ? Math.max(...st.map((s) => s.rssMB)) : null,
  };
});

const runID = `load-${aiMode}-${new Date().toISOString().replace(/[:.-]/g, "").slice(0, 15)}Z`;
const meta = {
  benchmark: "load", runID, timestamp: new Date().toISOString(), gitCommit: execSync("git rev-parse --short HEAD").toString().trim(),
  ai: aiMode === "mock" ? `MOCK provider, lognormal latency mean ${flag("--mock-latency", "300")} ms` : `REAL local model via Ollama (${process.env.OLLAMA_MODEL ?? "gemma3:27b"})`,
  limiter: Number(flag("--limit", "0")) > 0 ? { maxConcurrent: Number(flag("--limit")), maxQueue: Number(flag("--queue", "8")), maxWaitMs: Number(flag("--wait", "20000")) } : null,
  clientTimeoutMs, mode: perWorker ? `${perWorker} requests per worker` : `${seconds}s per stage`,
  environment: "single Node process server on macOS host (Apple M5 Pro), client in a separate process on the same machine, loopback network",
};
mkdirSync(join(root, "Results/Raw/load"), { recursive: true });
writeFileSync(join(root, "Results/Raw/load", `${runID}.json`), JSON.stringify({ metadata: meta, summary, samples }, null, 1));
for (const s of summary) {
  console.log(`c=${String(s.concurrency).padStart(3)} req=${String(s.requests).padStart(5)} rps=${s.throughput_rps.toFixed(1).padStart(7)} goodput=${s.goodput_rps.toFixed(2).padStart(7)} ok=${(s.success_rate * 100).toFixed(1).padStart(5)}% p50=${s.latency_ok_ms.p50?.toFixed(0)} p95=${s.latency_ok_ms.p95?.toFixed(0)} p99=${s.latency_ok_ms.p99?.toFixed(0) ?? "n/a"} cpu=${s.server_cpu_percent_mean?.toFixed(0)}% rss=${s.server_rss_mb_max?.toFixed(0)}MB ${JSON.stringify(s.statuses)}`);
}
console.log(`Wrote Results/Raw/load/${runID}.json`);
