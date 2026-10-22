import Fastify, { type FastifyReply, type FastifyRequest } from "fastify";
import rateLimit from "@fastify/rate-limit";
import { z } from "zod";
import { ConcurrencyLimiter, Overloaded } from "./ai/limiter.js";
import { AIProviderError, type LanguageAI } from "./ai/provider.js";
import { AppleIdentityVerifier, TokenService, type Subject } from "./auth/tokens.js";
import type { TransactionVerifier } from "./entitlements.js";
import type { Feature, MeteredAction, PlanCatalog, Tier } from "./quota/plans.js";
import { nextUtcMidnight, utcDay, type UsageStore } from "./quota/store.js";
import { explainWithRetrieval, retrieve } from "./rewind/pipeline.js";
import { ExplainRequest, LessonRequest, SuggestionsRequest, TutorRequest } from "./schemas.js";

export interface AppDeps {
  ai: LanguageAI;
  tokens: TokenService;
  apple: AppleIdentityVerifier;
  store: UsageStore;
  catalog: PlanCatalog;
  transactions: TransactionVerifier;
  logLevel?: string;
  /** Bounds concurrent AI calls; omit for no limit. */
  aiLimiter?: ConcurrencyLimiter;
  /** Where logs go (defaults to stdout). Lets tests inspect real log output. */
  logStream?: NodeJS.WritableStream;
  /** Phonetic candidate retrieval before the model (default on). */
  phoneticRetrieval?: boolean;
  /** Requests per minute per token. Default 60. Raised only by load tests. */
  rateLimitPerMinute?: number;
  now?: () => Date;
}

/** ISO 8601 without milliseconds, which Foundation's `.iso8601` strategy requires. */
export function iso(d: Date): string {
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}

declare module "fastify" {
  interface FastifyRequest {
    subject?: Subject;
  }
}

/**
 * Builds the HTTP API. Logging never includes request bodies: they contain
 * transcripts of private conversations.
 */
export async function buildApp(deps: AppDeps) {
  const now = deps.now ?? (() => new Date());
  const app = Fastify({
    logger: deps.logLevel === "silent" ? false : { level: deps.logLevel ?? "info", redact: ["req.headers.authorization"], ...(deps.logStream ? { stream: deps.logStream } : {}) },
    bodyLimit: 256 * 1024,
  });

  await app.register(rateLimit, {
    global: true,
    max: deps.rateLimitPerMinute ?? 60,
    timeWindow: "1 minute",
    // Keyed by bearer token when present so one device cannot exhaust a shared IP.
    keyGenerator: (req) => req.headers.authorization ?? req.ip,
  });

  // ---- helpers

  async function authenticate(req: FastifyRequest, reply: FastifyReply) {
    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    const subject = token ? await deps.tokens.verify(token) : null;
    if (!subject) return reply.code(401).send({ error: "unauthorized" });
    req.subject = subject;
  }

  async function tierOf(subject: Subject): Promise<Tier> {
    const ent = await deps.store.getEntitlement(subject);
    if (!ent || ent.tier === "free") return "free";
    if (ent.expiresAt && ent.expiresAt <= now()) return "free";
    return ent.tier;
  }

  /**
   * Checks plan feature + daily quota. Usage is recorded separately, only
   * after the AI call succeeds, so failures never cost the learner a question.
   */
  async function meter(req: FastifyRequest, reply: FastifyReply, action: MeteredAction, feature: Feature): Promise<boolean> {
    const subject = req.subject!;
    const plan = deps.catalog.plans[await tierOf(subject)];
    const limit = plan.daily_limits[action] ?? 0;
    if (!plan.features.includes(feature) || limit <= 0) {
      reply.code(403).send({ error: "feature_locked", feature });
      return false;
    }
    const day = utcDay(now());
    const used = (await deps.store.get(subject, day))[action] ?? 0;
    if (used >= limit) {
      reply.code(402).send({ error: "quota_exceeded", action, limit, resets_at: iso(nextUtcMidnight(now())) });
      return false;
    }
    return true;
  }

  async function consume(req: FastifyRequest, action: MeteredAction) {
    await deps.store.increment(req.subject!, utcDay(now()), action);
  }

  function parse<T extends z.ZodType>(schema: T, body: unknown, reply: FastifyReply): z.infer<T> | null {
    const result = schema.safeParse(body);
    if (!result.success) {
      reply.code(400).send({ error: "invalid_request", issues: result.error.issues.slice(0, 5).map((i) => ({ path: i.path.join("."), message: i.message })) });
      return null;
    }
    return result.data;
  }

  /** Runs an AI call through the concurrency limiter when one is configured. */
  const limited = <T>(task: () => Promise<T>): Promise<T> => (deps.aiLimiter ? deps.aiLimiter.run(task) : task());

  function aiFailure(error: unknown, reply: FastifyReply, req: FastifyRequest) {
    if (error instanceof Overloaded) {
      req.log.warn("ai at capacity; rejected fast");
      return reply.code(503).header("retry-after", String(error.retryAfterSeconds)).send({ error: "busy" });
    }
    if (error instanceof AIProviderError) {
      req.log.warn({ kind: error.kind }, "ai provider failure");
      if (error.kind === "rate_limited") return reply.code(429).header("retry-after", "5").send({ error: "rate_limited" });
      if (error.kind === "timeout") return reply.code(504).send({ error: "timeout" });
      if (error.kind === "unavailable") return reply.code(503).send({ error: "unavailable" });
      return reply.code(502).send({ error: error.kind });
    }
    req.log.error("unexpected failure");
    return reply.code(500).send({ error: "internal" });
  }

  // ---- public routes

  app.get("/healthz", async () => ({ ok: true }));

  app.get("/v1/config", async () => deps.catalog);

  // Issues a guest token for an app install. Strictly rate limited per IP.
  // Production hardening: require an App Attest assertion here (see docs/BACKEND.md).
  app.post("/v1/auth/install", { config: { rateLimit: { max: 10, timeWindow: "1 hour", keyGenerator: (req: FastifyRequest) => req.ip } } }, async (req, reply) => {
    const body = parse(z.object({ install_id: z.uuid() }), req.body, reply);
    if (!body) return;
    const { token, expiresAt } = await deps.tokens.issue(`install:${body.install_id.toLowerCase()}`, now());
    return { token, expires_at: iso(expiresAt), user_id: null };
  });

  // ---- authenticated routes

  app.register(async (scoped) => {
    scoped.addHook("preHandler", authenticate);

    scoped.post("/v1/auth/apple", async (req, reply) => {
      const body = parse(z.object({ identity_token: z.string().min(10).max(4_096) }), req.body, reply);
      if (!body) return;
      const appleSub = await deps.apple.verify(body.identity_token);
      if (!appleSub) return reply.code(401).send({ error: "invalid_identity_token" });
      const userSubject: Subject = `apple:${appleSub}`;
      if (req.subject!.startsWith("install:")) await deps.store.merge(req.subject!, userSubject, utcDay(now()));
      const { token, expiresAt } = await deps.tokens.issue(userSubject, now());
      return { token, expires_at: iso(expiresAt), user_id: appleSub };
    });

    scoped.get("/v1/usage", async (req) => {
      const tier = await tierOf(req.subject!);
      const day = utcDay(now());
      return { tier, day, used: await deps.store.get(req.subject!, day), limits: deps.catalog.plans[tier].daily_limits };
    });

    scoped.post("/v1/rewind/explain", async (req, reply) => {
      const body = parse(ExplainRequest, req.body, reply);
      if (!body) return;
      if (body.detail_level === "detailed") {
        const plan = deps.catalog.plans[await tierOf(req.subject!)];
        if (!plan.features.includes("detailed_explanations")) body.detail_level = "concise";
      }
      const started = Date.now();
      const retrieval = retrieve(body, deps.phoneticRetrieval ?? true);
      // Ambiguous "sounded like" questions are answered with a clarification
      // before any model call, so they cost no quota and no model time.
      if (retrieval?.kind === "ambiguous") {
        const { explanation, path } = await explainWithRetrieval(deps.ai, body, retrieval);
        req.log.info({ ms: Date.now() - started, status: explanation.status, path, lang: body.language }, "explain");
        return explanation;
      }
      if (!(await meter(req, reply, "rewind_question", "live_rewind"))) return;
      try {
        const { explanation, path } = await limited(() => explainWithRetrieval(deps.ai, body, retrieval));
        await consume(req, "rewind_question");
        // Latency only. Never log transcript or answer content.
        req.log.info({ ms: Date.now() - started, status: explanation.status, path, lang: body.language }, "explain");
        return explanation;
      } catch (error) {
        return aiFailure(error, reply, req);
      }
    });

    scoped.post("/v1/tutor/turn", async (req, reply) => {
      const body = parse(TutorRequest, req.body, reply);
      if (!body) return;
      if (!(await meter(req, reply, "tutor_turn", "conversation_practice"))) return;
      try {
        const turn = await limited(() => deps.ai.tutorTurn(body));
        await consume(req, "tutor_turn");
        return turn;
      } catch (error) {
        return aiFailure(error, reply, req);
      }
    });

    scoped.post("/v1/suggestions", async (req, reply) => {
      const body = parse(SuggestionsRequest, req.body, reply);
      if (!body) return;
      if (!(await meter(req, reply, "lesson_generation", "proactive_suggestions"))) return;
      try {
        const suggestions = await limited(() => deps.ai.suggestions(body));
        await consume(req, "lesson_generation");
        return suggestions;
      } catch (error) {
        return aiFailure(error, reply, req);
      }
    });

    scoped.post("/v1/lessons", async (req, reply) => {
      const body = parse(LessonRequest, req.body, reply);
      if (!body) return;
      if (!(await meter(req, reply, "lesson_generation", "personalized_lessons"))) return;
      try {
        const lesson = await limited(() => deps.ai.lesson(body));
        await consume(req, "lesson_generation");
        return lesson;
      } catch (error) {
        return aiFailure(error, reply, req);
      }
    });

    scoped.post("/v1/entitlements/verify", async (req, reply) => {
      const body = parse(z.object({ signed_transactions: z.array(z.string().max(16_384)).max(20) }), req.body, reply);
      if (!body) return;
      const result = await deps.transactions.resolve(body.signed_transactions, now());
      await deps.store.setEntitlement(req.subject!, result);
      return { tier: result.tier, expires_at: result.expiresAt ? iso(result.expiresAt) : null };
    });

    scoped.delete("/v1/account", async (req, reply) => {
      await deps.store.deleteSubject(req.subject!);
      return reply.code(204).send();
    });
  });

  return app;
}
