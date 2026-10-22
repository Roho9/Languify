// Live smoke test against the configured AI provider (AI_PROVIDER=ollama by
// default; AI_PROVIDER=claude needs ANTHROPIC_API_KEY). Uses a transcript captured from Apple's
// on-device ta-IN and en-IN recognisers during feasibility testing (see
// docs/FEASIBILITY.md). Text and mean confidences are real recogniser output;
// segment start/end times are approximate.
//   npm run smoke
import { createLanguageAI } from "../src/ai/factory.js";
import { loadConfig } from "../src/config.js";

// The smoke test never issues tokens, so a placeholder secret is fine here.
const config = loadConfig({ LANGUIFY_TOKEN_SECRET: "smoke-test-only-not-a-real-secret-value", ...process.env });
console.log(`Provider: ${config.AI_PROVIDER} (${config.AI_PROVIDER === "ollama" ? config.OLLAMA_MODEL : config.ANTHROPIC_MODEL})`);
const ai = createLanguageAI(config);

const cases = [
  { question: "What did that last sentence mean?", kind: "sentence" as const },
  { question: "What does the word that sounded like 'mudinjathum' mean?", kind: "word" as const },
  { question: "How would I respond in Tamil?", kind: "respond" as const },
];

for (const c of cases) {
  const started = Date.now();
  const result = await ai
    .explain({
      language: "ta",
      question: c.question,
      kind: c.kind,
      detail_level: "concise",
      transcript: {
        language_code: "ta",
        primary: [
          { text: "naan innaikku office meeting mudindiyathum veettukku", start: 0, end: 3.2, confidence: 0.93, alternatives: [] },
          { text: "varaen sariyaa", start: 3.2, end: 4.4, confidence: 0.67, alternatives: [] },
        ],
        english: [{ text: "Nani office, meeting, Mudindyadum, Bituk, Barin, Sariya.", start: 0, end: 4.4, confidence: 0.33, alternatives: [] }],
        window_seconds: 60,
      },
      learner: { comprehension: 4, speaking: 2, reading: 1, recent_words: [] },
    })
    .catch((error: Error) => error);
  console.log(`\n=== ${c.question} (${Date.now() - started} ms)`);
  console.log(result instanceof Error ? `ERROR: ${result.message}` : JSON.stringify(result, null, 2));
}
