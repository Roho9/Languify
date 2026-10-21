import Fastify, { type FastifyReply, type FastifyRequest } from "fastify";
import rateLimit from "@fastify/rate-limit";
import { z } from "zod";
import { AIProviderError, type LanguageAI } from "./ai/provider.js";
import { AppleIdentityVerifier, TokenService, type Subject } from "./auth/tokens.js";
import type { TransactionVerifier } from "./entitlements.js";
import type { Feature, MeteredAction, PlanCatalog, Tier } from "./quota/plans.js";
import { nextUtcMidnight, utcDay, type UsageStore } from "./quota/store.js";
import { ExplainRequest, LessonRequest, SuggestionsRequest, TutorRequest } from "./schemas.js";

export interface AppDeps {
  ai: LanguageAI;
  tokens: TokenService;
  apple: AppleIdentityVerifier;
  store: UsageStore;
  catalog: PlanCatalog;
  transactions: TransactionVerifier;
  logLevel?: string;
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
    logger: deps.logLevel === "silent" ? false : { level: deps.logLevel ?? "info", redact: ["req.headers.authorization"] },
    bodyLimit: 256 * 1024,
  });

  await app.register(rateLimit, {
    global: true,
    max: 60,
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

  function aiFailure(error: unknown, reply: FastifyReply, req: FastifyRequest) {
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
      if (!(await meter(req, reply, "rewind_question", "live_rewind"))) return;
      const started = Date.now();
      try {
        const explanation = await deps.ai.explain(body);
        await consume(req, "rewind_question");
        // Latency only. Never log transcript or answer content.
        req.log.info({ ms: Date.now() - started, status: explanation.status, lang: body.language }, "explain");
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
        const turn = await deps.ai.tutorTurn(body);
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
        const suggestions = await deps.ai.suggestions(body);
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
        const lesson = await deps.ai.lesson(body);
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
