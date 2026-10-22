import { describe, expect, it } from "vitest";
import { OllamaLanguageAI } from "../src/ai/ollama.js";
import { AIProviderError } from "../src/ai/provider.js";
import type { ExplainRequest } from "../src/schemas.js";

// TEST DOUBLE: a scripted fetch standing in for the Ollama server.
function fakeFetch(respond: (body: any) => Response | Promise<Response>) {
  const calls: any[] = [];
  const impl = (async (_url: URL, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body));
    calls.push(body);
    return respond(body);
  }) as unknown as typeof fetch;
  return { impl, calls };
}

const options = { baseUrl: "http://ollama.test", model: "gemma3:27b", timeoutMs: 1_000, keepAlive: "30m" };

const request: ExplainRequest = {
  language: "ta",
  question: "What did that sentence mean?",
  kind: "sentence",
  detail_level: "concise",
  transcript: {
    language_code: "ta",
    primary: [{ text: "naan innaikku office meeting mudindiyathum veettukku varaen", start: 0, end: 3, confidence: 0.9, alternatives: [] }],
    english: [],
    window_seconds: 60,
  },
  learner: { comprehension: 4, speaking: 2, reading: 1, recent_words: [] },
};

const answer = {
  status: "answered",
  kind: "sentence",
  spoken_summary: "They said they'll come home after the office meeting.",
  heard: {
    native_script: "நான் இன்னைக்கு ஆபீஸ் மீட்டிங் முடிஞ்சதும் வீட்டுக்கு வரேன்",
    transliteration: "naan innaikku office meeting mudinjathum veettukku varen",
    english_natural: "I'll come home today after the office meeting.",
    literal_gloss: null,
  },
  items: [],
  suggested_replies: [],
  grammar_note: null,
  clarification: null,
  alternatives: [],
  uncertainty_note: null,
};

const reply = (content: unknown, status = 200) =>
  new Response(JSON.stringify({ message: { role: "assistant", content: typeof content === "string" ? content : JSON.stringify(content) } }), { status });

describe("OllamaLanguageAI", () => {
  it("sends the schema, prompts and model, and parses the answer", async () => {
    const { impl, calls } = fakeFetch(() => reply(answer));
    const result = await new OllamaLanguageAI(options, impl).explain(request);
    expect(result.heard?.english_natural).toContain("office meeting");
    expect(calls[0].model).toBe("gemma3:27b");
    expect(calls[0].stream).toBe(false);
    expect(calls[0].format.type).toBe("object");
    expect(calls[0].format.required).toContain("spoken_summary");
    expect(calls[0].messages[0].role).toBe("system");
    expect(calls[0].messages[1].content).toContain("<transcript");
  });

  it("rejects output that is not JSON", async () => {
    const { impl } = fakeFetch(() => reply("Sure! Here is the explanation..."));
    await expect(new OllamaLanguageAI(options, impl).explain(request)).rejects.toMatchObject({ kind: "invalid_output" });
  });

  it("rejects JSON that does not match the schema", async () => {
    const { impl } = fakeFetch(() => reply({ status: "answered", spoken_summary: "hi" }));
    await expect(new OllamaLanguageAI(options, impl).explain(request)).rejects.toMatchObject({ kind: "invalid_output" });
  });

  it("applies the same semantic checks as Claude", async () => {
    const { impl } = fakeFetch(() => reply({ ...answer, heard: null }));
    await expect(new OllamaLanguageAI(options, impl).explain(request)).rejects.toThrow(/answered without content/);
  });

  it("explains how to fix a missing model", async () => {
    const { impl } = fakeFetch(() => new Response("model not found", { status: 404 }));
    const error = await new OllamaLanguageAI(options, impl).explain(request).catch((e) => e);
    expect(error).toBeInstanceOf(AIProviderError);
    expect(error.kind).toBe("unavailable");
    expect(error.message).toContain("ollama pull gemma3:27b");
  });

  it("maps a stopped server to unavailable", async () => {
    const impl = (async () => {
      throw new TypeError("fetch failed");
    }) as unknown as typeof fetch;
    await expect(new OllamaLanguageAI(options, impl).explain(request)).rejects.toMatchObject({ kind: "unavailable" });
  });

  it("maps a slow model to timeout", async () => {
    const impl = (async (_url: URL, init?: RequestInit) =>
      new Promise((_, reject) => init?.signal?.addEventListener("abort", () => reject(init.signal!.reason)))) as unknown as typeof fetch;
    await expect(new OllamaLanguageAI({ ...options, timeoutMs: 20 }, impl).explain(request)).rejects.toMatchObject({ kind: "timeout" });
  });
});
