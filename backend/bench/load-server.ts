// Server process for load tests. Prints "READY <port>" then a JSON stats line
// every 500 ms (CPU, memory, limiter state) so the client can attribute
// resource use to load stages without measuring itself.
//
// Env: LOAD_AI=mock|real, MOCK_LATENCY_MS (mean, lognormal), LIMIT_CONCURRENCY,
// LIMIT_QUEUE, LIMIT_WAIT_MS, LANGUIFY_TOKEN_SECRET
import { buildApp } from "../src/app.js";
import { createLanguageAI } from "../src/ai/factory.js";
import { ConcurrencyLimiter } from "../src/ai/limiter.js";
import type { LanguageAI } from "../src/ai/provider.js";
import { AppleIdentityVerifier, TokenService } from "../src/auth/tokens.js";
import { loadConfig } from "../src/config.js";
import { DEFAULT_CATALOG, type PlanCatalog } from "../src/quota/plans.js";
import { InMemoryUsageStore } from "../src/quota/store.js";
import type { Explanation } from "../src/schemas.js";

const env = process.env;
const secret = env.LANGUIFY_TOKEN_SECRET ?? "load-test-secret-load-test-secret-123";

// MOCK provider for infrastructure stress tests: fixed valid answer after a
// lognormal delay. Never used outside load tests; results are labelled mock.
const answer: Explanation = {
  status: "answered", kind: "word", spoken_summary: "Madi means laziness.", heard: null,
  items: [{ native_script: "மடி", transliteration: "madi", english_meaning: "laziness", contextual_meaning: "being lazy", pronunciation_hint: "MA-di", part_of_speech: "noun", register: "informal", usage_note: null, cultural_note: null, regional_note: null, example: null, related: [] }],
  suggested_replies: [], grammar_note: null, clarification: null, alternatives: [], uncertainty_note: null,
};
const meanMs = Number(env.MOCK_LATENCY_MS ?? "300");
const delay = () => {
  // Lognormal with sigma 0.35 around the requested mean.
  const z = Math.sqrt(-2 * Math.log(Math.random() || 1e-9)) * Math.cos(2 * Math.PI * Math.random());
  return meanMs * Math.exp(0.35 * z - 0.35 ** 2 / 2);
};
const mockAI: LanguageAI = {
  explain: () => new Promise((r) => setTimeout(() => r(answer), delay())),
  tutorTurn: () => Promise.reject(new Error("not used")),
  suggestions: () => Promise.reject(new Error("not used")),
  lesson: () => Promise.reject(new Error("not used")),
};

const ai = env.LOAD_AI === "real" ? createLanguageAI(loadConfig({ ...env, LANGUIFY_TOKEN_SECRET: secret })) : mockAI;

// Generous limits so the test measures capacity, not the product's quotas.
const catalog: PlanCatalog = structuredClone(DEFAULT_CATALOG);
catalog.plans.free.daily_limits.rewind_question = 1_000_000_000;

const limit = Number(env.LIMIT_CONCURRENCY ?? "0");
const limiter = limit > 0 ? new ConcurrencyLimiter(limit, Number(env.LIMIT_QUEUE ?? "8"), Number(env.LIMIT_WAIT_MS ?? "20000")) : undefined;

const app = await buildApp({
  ai,
  tokens: new TokenService(secret),
  apple: new AppleIdentityVerifier("app.languify.Languify", async () => { throw new Error("unused"); }),
  store: new InMemoryUsageStore(),
  catalog,
  transactions: { resolve: async () => ({ tier: "free", expiresAt: null }) },
  logLevel: "silent",
  aiLimiter: limiter,
  rateLimitPerMinute: Number(env.RATE_LIMIT ?? "1000000"),
});
await app.listen({ port: 0, host: "127.0.0.1" });
const address = app.server.address();
console.log(`READY ${typeof address === "object" && address ? address.port : 0}`);

let lastCpu = process.cpuUsage();
let lastTime = process.hrtime.bigint();
setInterval(() => {
  const cpu = process.cpuUsage(lastCpu);
  const now = process.hrtime.bigint();
  const wallMs = Number(now - lastTime) / 1e6;
  lastCpu = process.cpuUsage();
  lastTime = now;
  console.log(JSON.stringify({
    t: Date.now(), cpuPercent: ((cpu.user + cpu.system) / 1000 / wallMs) * 100,
    rssMB: process.memoryUsage().rss / 1048576, heapMB: process.memoryUsage().heapUsed / 1048576,
    limiter: limiter?.stats ?? null,
  }));
}, 500).unref();
