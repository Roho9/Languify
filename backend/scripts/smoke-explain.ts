// Live smoke test against the real Claude API. Requires ANTHROPIC_API_KEY (or
// an `ant auth login` profile). Uses a transcript captured from Apple's
// on-device ta-IN and en-IN recognisers during feasibility testing (see
// docs/FEASIBILITY.md). Text and mean confidences are real recogniser output;
// segment start/end times are approximate.
//   npx tsx scripts/smoke-explain.ts
import Anthropic from "@anthropic-ai/sdk";
import { ClaudeLanguageAI } from "../src/ai/claude.js";

const ai = new ClaudeLanguageAI(new Anthropic(), {
  model: process.env.ANTHROPIC_MODEL ?? "claude-opus-5-5",
  rewindEffort: "low",
  tutorEffort: "low",
  lessonEffort: "medium",
  timeoutMs: 30_000,
});

const cases = [
  { question: "What did that last sentence mean?", kind: "sentence" as const },
  { question: "What does the word that sounded like 'mudinjathum' mean?", kind: "word" as const },
  { question: "How would I respond in Tamil?", kind: "respond" as const },
];

for (const c of cases) {
  const started = Date.now();
  const result = await ai.explain({
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
  });
  console.log(`\n=== ${c.question} (${Date.now() - started} ms)`);
  console.log(JSON.stringify(result, null, 2));
}
