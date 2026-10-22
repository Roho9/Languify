import { Writable } from "node:stream";
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { AppleIdentityVerifier, TokenService } from "../src/auth/tokens.js";
import { AIProviderError, type LanguageAI } from "../src/ai/provider.js";
import { DEFAULT_CATALOG } from "../src/quota/plans.js";
import { InMemoryUsageStore } from "../src/quota/store.js";

// Privacy requirement: transcripts and AI answers never reach server logs.
describe("privacy: server logs exclude conversation content", () => {
  const SECRET_PHRASE = "amma-secret-family-sentence-xyz";
  const ANSWER_PHRASE = "answer-text-that-must-not-be-logged";

  async function runWithLogs(ai: LanguageAI) {
    const lines: string[] = [];
    const sink = new Writable({ write(chunk, _enc, cb) { lines.push(chunk.toString()); cb(); } });
    const app = await buildApp({
      ai,
      tokens: new TokenService("privacy-test-secret-privacy-test-secret"),
      apple: new AppleIdentityVerifier("app.languify.Languify", async () => { throw new Error("unused"); }),
      store: new InMemoryUsageStore(),
      catalog: DEFAULT_CATALOG,
      transactions: { resolve: async () => ({ tier: "free" as const, expiresAt: null }) },
      logLevel: "trace",
      logStream: sink,
    });
    const { token } = await new TokenService("privacy-test-secret-privacy-test-secret").issue("install:privacy");
    await app.inject({
      method: "POST", url: "/v1/rewind/explain", headers: { authorization: `Bearer ${token}` },
      payload: {
        language: "ta", question: `what did ${SECRET_PHRASE} mean`, kind: "word", sounds_like: SECRET_PHRASE, user_context: SECRET_PHRASE,
        transcript: { language_code: "ta", primary: [{ text: SECRET_PHRASE, start: 0, end: 1, confidence: 0.9, alternatives: [] }], english: [], window_seconds: 30 },
        learner: { comprehension: 3, speaking: 2, reading: 1, recent_words: [] },
      },
    });
    sink.end();
    return lines.join("");
  }

  const answering: LanguageAI = {
    explain: async () => ({ status: "answered", kind: "word", spoken_summary: ANSWER_PHRASE, heard: { native_script: "", transliteration: ANSWER_PHRASE, english_natural: ANSWER_PHRASE, literal_gloss: null }, items: [], suggested_replies: [], grammar_note: null, clarification: null, alternatives: [], uncertainty_note: null }),
    tutorTurn: async () => { throw new Error(); }, suggestions: async () => { throw new Error(); }, lesson: async () => { throw new Error(); },
  };

  it("successful request logs no transcript or answer text, even at trace level", async () => {
    const logs = await runWithLogs(answering);
    expect(logs.length).toBeGreaterThan(0);
    expect(logs).not.toContain(SECRET_PHRASE);
    expect(logs).not.toContain(ANSWER_PHRASE);
    expect(logs).toContain("explain");
  });

  it("failed request logs no transcript text", async () => {
    const failing: LanguageAI = { ...answering, explain: async () => { throw new AIProviderError("provider failed", "invalid_output"); } };
    const logs = await runWithLogs(failing);
    expect(logs).toContain("ai provider failure");
    expect(logs).not.toContain(SECRET_PHRASE);
  });
});
